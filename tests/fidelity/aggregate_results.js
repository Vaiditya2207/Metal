#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const RESULTS_DIR = path.join(__dirname, 'results');
const GOOGLE_TARGET = 'https://www.google.com';

function runCommand(cmd) {
    console.log(`Running: ${cmd}`);
    try {
        return execSync(cmd, { stdio: 'pipe' }).toString();
    } catch (e) {
        return e.stdout?.toString() || e.stderr?.toString() || e.message;
    }
}

async function main() {
    console.log('--- Fidelity Benchmarking ---');

    // 1. Run DOM Fidelity (all + Google)
    console.log('Running all DOM Fidelity tests...');
    const domOutput = runCommand('./run_test.sh --all');
    console.log('Running DOM Fidelity for Google...');
    const domGoogleOutput = runCommand(`./run_test.sh ${GOOGLE_TARGET}`);
    
    // 2. Run Visual Fidelity (all + Google)
    console.log('Running all Visual Fidelity tests...');
    const visualOutput = runCommand('./run_visual_test.sh --all');
    console.log('Running Visual Fidelity for Google...');
    const visualGoogleOutput = runCommand(`./run_visual_test.sh ${GOOGLE_TARGET}`);

    // 3. Extract results for Google
    const domGoogleMatch = domGoogleOutput.match(/Accuracy: ([\d.]+)%/);
    const domGoogleAccuracy = domGoogleMatch ? parseFloat(domGoogleMatch[1]) : 0;

    const visualGoogleMatch = visualGoogleOutput.match(/Match: ([\d.]+)%/);
    const visualGoogleAccuracy = visualGoogleMatch ? parseFloat(visualGoogleMatch[1]) : 0;

    // 4. Extract overview table from visualOutput
    // It looks like:
    //   Page                      Match
    //   01_simple                 97.74%
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

    // 5. Generate PR Comment Markdown
    let summaryMd = `## 📊 Fidelity Benchmark Results\n\n`;
    
    summaryMd += `### 🌐 Google.com (Gatekeeper)\n`;
    const status = domGoogleAccuracy >= 85 ? "✅ PASS" : "❌ FAIL (Under 85%)";
    summaryMd += `- **DOM Accuracy:** ${domGoogleAccuracy}%\n`;
    summaryMd += `- **Visual Match:** ${visualGoogleAccuracy}%\n`;
    summaryMd += `- **Status:** ${status}\n\n`;

    summaryMd += `### 📄 Test Pages Overview\n\n`;
    summaryMd += `| Page | Visual Match |\n`;
    summaryMd += `| :--- | :---: |\n`;
    for (const row of visualTable) {
        summaryMd += `| ${row.name} | ${row.match} |\n`;
    }

    summaryMd += `\n*Note: High DPI (Retina) scaling is applied to Metal screenshots before comparison.*\n`;
    
    fs.mkdirSync(RESULTS_DIR, { recursive: true });
    fs.writeFileSync(path.join(RESULTS_DIR, 'pr_comment.md'), summaryMd);
    console.log('PR comment summary written to results/pr_comment.md');

    if (domGoogleAccuracy < 85) {
        console.error(`ERROR: Google.com DOM Accuracy (${domGoogleAccuracy}%) is below 85%`);
        process.exit(1);
    }
}

main();
