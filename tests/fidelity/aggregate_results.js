#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const RESULTS_DIR = path.join(__dirname, 'results');
const GOOGLE_TARGET = 'https://www.google.com';
const PROJECT_ROOT = path.resolve(__dirname, '../..');

function runCommand(cmd, cwd = __dirname) {
    console.log(`Running: ${cmd} in ${cwd}`);
    try {
        return {
            output: execSync(cmd, { cwd, stdio: 'pipe' }).toString(),
            success: true
        };
    } catch (e) {
        return {
            output: e.stdout?.toString() || e.stderr?.toString() || e.message,
            success: false
        };
    }
}

async function main() {
    console.log('=== Metal CI Comprehensive Report ===');

    // 1. Run Unit Tests
    console.log('Running Zig Engine Unit Tests...');
    const unitResult = runCommand('zig build test', PROJECT_ROOT);
    const unitStatus = unitResult.success ? "✅ PASSED" : "❌ FAILED";

    // 2. Run DOM Fidelity (all + Google)
    console.log('Running all DOM Fidelity tests...');
    const domOutput = runCommand('./run_test.sh --all').output;
    console.log('Running DOM Fidelity for Google...');
    const domGoogleOutput = runCommand(`./run_test.sh ${GOOGLE_TARGET}`).output;
    
    // 3. Run Visual Fidelity (all + Google)
    console.log('Running all Visual Fidelity tests...');
    const visualOutput = runCommand('./run_visual_test.sh --all').output;
    console.log('Running Visual Fidelity for Google...');
    const visualGoogleOutput = runCommand(`./run_visual_test.sh ${GOOGLE_TARGET}`).output;

    // 4. Extract results for Google
    const domGoogleMatch = domGoogleOutput.match(/Accuracy: ([\d.]+)%/);
    const domGoogleAccuracy = domGoogleMatch ? parseFloat(domGoogleMatch[1]) : 0;

    const visualGoogleMatch = visualGoogleOutput.match(/Match: ([\d.]+)%/);
    const visualGoogleAccuracy = visualGoogleMatch ? parseFloat(visualGoogleMatch[1]) : 0;

    // 5. Extract overview table from visualOutput
    const visualTable = [];
    const tableLines = visualOutput.split('\n');
    let inTable = false;
    for (const line of tableLines) {
        if (line.includes('Page') && line.includes('Match')) { inTable = true; continue; }
        if (inTable && line.trim().startsWith('===')) { inTable = false; continue; }
        if (inTable) {
            const parts = line.trim().split(/\s+/);
            if (parts.length >= 2) {
                visualTable.push({ name: parts[0], match: parts[1] });
            }
        }
    }

    // 6. Generate PR Comment Markdown
    let summaryMd = `## 🚀 Metal CI: Unified Report\n\n`;
    
    summaryMd += `### 🧠 Logic & Engine\n`;
    summaryMd += `- **Unit Tests:** ${unitStatus}\n\n`;

    summaryMd += `### 🌐 Google.com Benchmark (Gatekeeper)\n`;
    const googleStatus = domGoogleAccuracy >= 85 ? "✅ PASS" : "❌ FAIL (Under 85%)";
    summaryMd += `| Metric | Accuracy | Status |\n`;
    summaryMd += `| :--- | :---: | :---: |\n`;
    summaryMd += `| DOM Fidelity | ${domGoogleAccuracy}% | ${googleStatus} |\n`;
    summaryMd += `| Visual Match | ${visualGoogleAccuracy}% | - |\n\n`;

    summaryMd += `### 📄 Visual Fidelity Suite\n\n`;
    summaryMd += `| Page | Visual Match |\n`;
    summaryMd += `| :--- | :---: |\n`;
    for (const row of visualTable) {
        summaryMd += `| ${row.name} | ${row.match} |\n`;
    }

    summaryMd += `\n*Artifacts containing full logs and comparison screenshots are available in the Actions tab.*\n`;
    
    fs.mkdirSync(RESULTS_DIR, { recursive: true });
    fs.writeFileSync(path.join(RESULTS_DIR, 'pr_comment.md'), summaryMd);
    console.log('Detailed PR comment summary written to results/pr_comment.md');

    // Final Gatekeeper Logic
    if (!unitResult.success) {
        console.error('ERROR: Unit tests failed.');
        process.exit(1);
    }
    if (domGoogleAccuracy < 85) {
        console.error(`ERROR: Google.com DOM Accuracy (${domGoogleAccuracy}%) is below 85%`);
        process.exit(1);
    }
}

main();
