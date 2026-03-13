const std = @import("std");
const parser = @import("parser.zig");

const ua_css =
    \\h1 { display: block; font-size: 2em; font-weight: 700; margin-top: 0.67em; margin-bottom: 0.67em }
    \\h2 { display: block; font-size: 1.5em; font-weight: 700; margin-top: 0.83em; margin-bottom: 0.83em }
    \\h3 { display: block; font-size: 1.17em; font-weight: 700; margin-top: 1em; margin-bottom: 1em }
    \\h4 { display: block; font-size: 1em; font-weight: 700; margin-top: 1.33em; margin-bottom: 1.33em }
    \\h5 { display: block; font-size: 0.83em; font-weight: 700; margin-top: 1.67em; margin-bottom: 1.67em }
    \\h6 { display: block; font-size: 0.67em; font-weight: 700; margin-top: 2.33em; margin-bottom: 2.33em }
    \\p { display: block; margin-top: 1em; margin-bottom: 1em }
    \\ul { display: block; margin-top: 1em; margin-bottom: 1em; padding-left: 40px; list-style-type: disc }
    \\ol { display: block; margin-top: 1em; margin-bottom: 1em; padding-left: 40px; list-style-type: decimal }
    \\li { display: block }
    \\strong { font-weight: 700 }
    \\b { font-weight: 700 }
    \\em { font-style: italic }
    \\i { font-style: italic }
    \\cite { font-style: italic }
    \\var { font-style: italic }
    \\dfn { font-style: italic }
    \\a { color: #0000ee; text-decoration: underline }
    \\code { font-family: monospace }
    \\pre { display: block; font-family: monospace; margin-top: 1em; margin-bottom: 1em; white-space: pre }
    \\blockquote { display: block; margin-top: 1em; margin-bottom: 1em; margin-left: 40px; margin-right: 40px }
    \\div { display: block }
    \\body { display: block; background-color: #ffffff; color: #000000; margin: 8px }
    \\html { display: block; background-color: #ffffff; min-height: 100vh }
    \\head { display: none }
    \\title { display: none }
    \\style { display: none }
    \\script { display: none }
    \\link { display: none }
    \\meta { display: none }
    \\noscript { display: none }
    \\span { display: inline }
    \\img { display: inline-block; max-width: 100% }
    \\svg { display: inline-block }
    \\video { display: inline-block }
    \\canvas { display: inline-block }
    \\br { display: block }
    \\input { display: inline-block; padding-left: 4px; padding-right: 4px; padding-top: 2px; padding-bottom: 2px; border-width: 1px }
    \\button { display: inline-block; padding-left: 4px; padding-right: 4px; padding-top: 2px; padding-bottom: 2px; border-width: 1px }
    \\form { display: block }
    \\table { display: table }
    \\tr { display: table-row }
    \\td { display: table-cell }
    \\th { display: table-cell; font-weight: bold; text-align: center }
    \\footer { display: block }
    \\header { display: block }
    \\nav { display: block }
    \\main { display: block }
    \\section { display: block }
    \\article { display: block }
    \\aside { display: block }
    \\center { display: block; text-align: center }
    \\textarea { display: inline-block; padding-left: 4px; padding-right: 4px; padding-top: 2px; padding-bottom: 2px; border-width: 1px }
    \\hr { display: block; margin-top: 0.5em; margin-bottom: 0.5em }
    \\dd { display: block; margin-left: 40px }
    \\dl { display: block; margin-top: 1em; margin-bottom: 1em }
    \\dt { display: block }
    \\fieldset { display: block; margin-left: 2px; margin-right: 2px; padding-top: 0.35em; padding-bottom: 0.625em; padding-left: 0.75em; padding-right: 0.75em }
    \\legend { display: block; padding-left: 2px; padding-right: 2px }
    \\figure { display: block; margin-top: 1em; margin-bottom: 1em; margin-left: 40px; margin-right: 40px }
    \\figcaption { display: block }
    \\address { display: block }
    \\details { display: block }
    \\summary { display: block }
    \\dialog { display: none }
;

pub fn getStylesheet(allocator: std.mem.Allocator) !parser.Stylesheet {
    return try parser.Parser.parse(allocator, ua_css);
}
