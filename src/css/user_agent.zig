const std = @import("std");
const parser = @import("parser.zig");

const ua_css =
    \\h1 { display: block; font-size: 32px; font-weight: 700; margin-top: 21px; margin-bottom: 21px }
    \\h2 { display: block; font-size: 24px; font-weight: 700; margin-top: 19px; margin-bottom: 19px }
    \\h3 { display: block; font-size: 19px; font-weight: 700; margin-top: 18px; margin-bottom: 18px }
    \\h4 { display: block; font-size: 16px; font-weight: 700; margin-top: 21px; margin-bottom: 21px }
    \\h5 { display: block; font-size: 13px; font-weight: 700; margin-top: 22px; margin-bottom: 22px }
    \\h6 { display: block; font-size: 11px; font-weight: 700; margin-top: 24px; margin-bottom: 24px }
    \\p { display: block; margin-top: 16px; margin-bottom: 16px }
    \\ul { display: block; margin-top: 16px; margin-bottom: 16px; padding-left: 40px }
    \\ol { display: block; margin-top: 16px; margin-bottom: 16px; padding-left: 40px }
    \\li { display: block }
    \\strong { font-weight: 700 }
    \\em { font-weight: 400 }
    \\a { color: #2563eb }
    \\code { font-family: monospace }
    \\pre { display: block; font-family: monospace; margin-top: 16px; margin-bottom: 16px }
    \\blockquote { display: block; margin-top: 16px; margin-bottom: 16px; margin-left: 40px; margin-right: 40px }
    \\div { display: block }
    \\body { display: block }
    \\html { display: block }
    \\head { display: none }
    \\style { display: none }
    \\script { display: none }
;

pub fn getStylesheet(allocator: std.mem.Allocator) !parser.Stylesheet {
    return try parser.Parser.parse(allocator, ua_css);
}
