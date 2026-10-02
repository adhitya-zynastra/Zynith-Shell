pragma Singleton

import Quickshell
import "IconMap.js" as Map

Singleton {
    function glyph(name: string): string {
        return Map.glyphs[name] || "";
    }
}
