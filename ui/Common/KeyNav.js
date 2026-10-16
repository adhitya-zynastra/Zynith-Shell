.pragma library
// Moving the keyboard through a panel made of modules ("zones"), each a grid of stops filled row by row:
// zones: [{ count, cols }] in reading order; pos: { zone, stop } (zone -1: nowhere yet).
//   tab / backtab    the next / previous zone that has stops, at its first stop (wrapping round)
//   left / right     the previous / next stop in the zone (held at its ends)
//   up / down        a row up / down in the zone; past its first or last row, on to the zone before or after
//                    (its last row's nearest column going up, its first going down), held at the panel's ends
// Nothing selected yet, any move lands on the first stop of the first zone (backtab and up: the last zone).

function firstZone(zones, from, by) {
    var n = zones.length;
    for (var k = 0; k < n; k++) {
        var z = ((from + by * k) % n + n) % n;
        if (zones[z].count > 0)
            return z;
    }
    return -1;
}

function move(zones, pos, key) {
    if (zones.length === 0 || firstZone(zones, 0, 1) < 0)
        return { zone: -1, stop: -1 };
    if (pos.zone < 0 || pos.zone >= zones.length || zones[pos.zone].count === 0) {
        var back = key === "backtab" || key === "up";
        var z0 = back ? firstZone(zones, zones.length - 1, -1) : firstZone(zones, 0, 1);
        return { zone: z0, stop: 0 };
    }
    var zone = zones[pos.zone];
    var cols = Math.max(1, zone.cols || 1);
    var stop = Math.max(0, Math.min(zone.count - 1, pos.stop));
    switch (key) {
    case "tab":
        return { zone: firstZone(zones, pos.zone + 1, 1), stop: 0 };
    case "backtab":
        return { zone: firstZone(zones, pos.zone - 1, -1), stop: 0 };
    case "left":
        return { zone: pos.zone, stop: Math.max(0, stop - 1) };
    case "right":
        return { zone: pos.zone, stop: Math.min(zone.count - 1, stop + 1) };
    case "down": {
        if (stop + cols < zone.count)
            return { zone: pos.zone, stop: stop + cols };
        // the last row: a shorter last row still takes a step down from the row above it
        var lastRowStart = Math.floor((zone.count - 1) / cols) * cols;
        if (stop < lastRowStart)
            return { zone: pos.zone, stop: zone.count - 1 };
        for (var z = pos.zone + 1; z < zones.length; z++)
            if (zones[z].count > 0)
                return { zone: z, stop: Math.min(stop % cols, Math.min(zones[z].count, Math.max(1, zones[z].cols || 1)) - 1) };
        return { zone: pos.zone, stop: stop };
    }
    case "up": {
        if (stop - cols >= 0)
            return { zone: pos.zone, stop: stop - cols };
        for (var y = pos.zone - 1; y >= 0; y--) {
            var c = zones[y].count;
            if (c === 0)
                continue;
            var yc = Math.max(1, zones[y].cols || 1);
            var start = Math.floor((c - 1) / yc) * yc;
            return { zone: y, stop: Math.min(c - 1, start + (stop % cols)) };
        }
        return { zone: pos.zone, stop: stop };
    }
    }
    return pos;
}
