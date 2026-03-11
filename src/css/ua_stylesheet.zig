pub const default_css = 
    \\/* Structural & Head Elements */
    \\head, title, meta, link, script, style, template, dialog, area, base, col, command, datalist, embed, input[type="hidden"], keygen, menuitem, noembed, noframes, param, source, track { display: none; }
    \\
    \\/* Block Elements */
    \\html, body, div, p, h1, h2, h3, h4, h5, h6, ul, ol, li, dl, dt, dd, 
    \\address, article, aside, blockquote, canvas, dd, dl, dt, fieldset, 
    \\figcaption, figure, footer, form, header, hgroup, hr, main, nav, 
    \\noscript, pre, section, table, center { display: block; }
    \\
    \\/* Flex & Grid (Metal currently maps these to block fallback or minimal rules) */
    \\/* We add them here so they don't default to inline */
    \\body { display: block; /* often overridden to flex */ margin: 8px; }
    \\
    \\/* Tables */
    \\table { display: table; border-collapse: separate; box-sizing: border-box; border-spacing: 2px; }
    \\thead { display: table-header-group; vertical-align: middle; }
    \\tbody { display: table-row-group; vertical-align: middle; }
    \\tfoot { display: table-footer-group; vertical-align: middle; }
    \\tr { display: table-row; vertical-align: inherit; }
    \\td, th { display: table-cell; vertical-align: inherit; }
    \\
    \\/* HN Fake Intrinsic Table Rules */
    \\td[align="right"] { width: 24px; }
    \\td.votelinks { width: 14px; }
    \\
    \\/* Typography Basics */
    \\h1 { font-size: 2em; font-weight: bold; margin: 0.67em 0; }
    \\h2 { font-size: 1.5em; font-weight: bold; margin: 0.83em 0; }
    \\h3 { font-size: 1.17em; font-weight: bold; margin: 1em 0; }
    \\h4 { font-size: 1em; font-weight: bold; margin: 1.33em 0; }
    \\h5 { font-size: 0.83em; font-weight: bold; margin: 1.67em 0; }
    \\h6 { font-size: 0.67em; font-weight: bold; margin: 2.33em 0; }
    \\p, ul, ol, dl, blockquote, pre, figure { margin: 1em 0; }
    \\center { text-align: center; }
    \\ul, ol { padding-left: 40px; }
    \\
    \\/* Inline elements (Default is inline, but setting explicitly for clarity) */
    \\a, span, b, i, u, em, strong, code, kbd, samp, var, sub, sup, mark, q, small, abbr, time { display: inline; }
    \\
    \\/* Media */
    \\img, video, audio, embed, object, iframe { display: inline-block; }
    \\svg { display: inline; }
    \\
    \\/* Forms */
    \\button, input, select, textarea { display: inline-block; margin: 0; }
    \\
    \\/* Miscellaneous */
    \\hr { display: block; height: 1px; border: 1px inset; margin: 0.5em auto; }
    \\
;
