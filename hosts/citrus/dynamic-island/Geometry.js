function finite(value, fallback) {
    return typeof value === "number" && isFinite(value) ? value : fallback;
}

function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value));
}

function springCurve(damping) {
    var zeta = finite(damping, 0.8);
    var settle = 8;
    // ponytail: Qt 6.11.1 BezierEase has 10 fixed slots; keep 8 until storage is dynamic.
    var segments = 8;
    var curve = [];
    var i;

    zeta = Math.max(0.05, Math.min(1, zeta));

    // q = natural frequency * time; the unit-step response is normalized below.
    function response(u) {
        var q;
        var error;
        var root;
        var a;

        if (zeta < 1) {
            q = settle * u / zeta;
            root = Math.sqrt(1 - zeta * zeta);
            a = zeta / root;
            error = Math.exp(-zeta * q) * (Math.cos(root * q) + a * Math.sin(root * q));
            return 1 - error;
        }
        if (zeta === 1) {
            q = settle * u;
            return 1 - Math.exp(-q) * (1 + q);
        }
    }

    function slope(u) {
        var q;
        var root;

        if (zeta < 1) {
            q = settle * u / zeta;
            root = Math.sqrt(1 - zeta * zeta);
            return settle / zeta * Math.exp(-zeta * q) * Math.sin(root * q) / root;
        }
        if (zeta === 1) {
            q = settle * u;
            return settle * q * Math.exp(-q);
        }
    }

    var endpoint = response(1);
    if (!isFinite(endpoint) || endpoint === 0) {
        endpoint = 1;
    }

    for (i = 0; i < segments; i += 1) {
        var t0 = i / segments;
        var t1 = (i + 1) / segments;
        var dt = t1 - t0;
        var y0 = response(t0) / endpoint;
        var y1 = response(t1) / endpoint;
        var s0 = slope(t0) / endpoint;
        var s1 = slope(t1) / endpoint;

        if (i === segments - 1) {
            y1 = 1;
        }
        curve.push(
            t0 + dt / 3,
            y0 + s0 * dt / 3,
            t1 - dt / 3,
            y1 - s1 * dt / 3,
            t1,
            y1
        );
    }

    return curve;
}

function numberText(value) {
    var rounded = Math.round(value * 1000) / 1000;
    return String(rounded === 0 ? 0 : rounded);
}

function outline(width, height, morph, flare, radius) {
    var w = Math.max(0, finite(width, 0));
    var h = Math.max(0, finite(height, 0));
    var p = clamp(finite(morph, 0), 0, 1);
    var requestedFlare = Math.max(0, finite(flare, 14));
    var requestedRadius = Math.max(0, finite(radius, 19));
    var bottomRadius = Math.min(requestedRadius, w / 2, h / 2);
    var topRadius = bottomRadius * (1 - Math.min(1, p * 2));
    var maxFlare = Math.min(requestedFlare, w / 2, Math.max(0, h - bottomRadius - topRadius));
    var notch = Math.max(0, Math.min(1, (p - 0.5) * 2));
    var f = maxFlare * notch;
    var startY = topRadius + f;
    var path = [];

    path.push("M", numberText(topRadius), "0");
    path.push("H", numberText(w - topRadius));
    path.push("Q", numberText(w - f), "0", numberText(w - f), numberText(startY));
    path.push("V", numberText(h - bottomRadius));
    path.push("Q", numberText(w - f), numberText(h), numberText(w - f - bottomRadius), numberText(h));
    path.push("H", numberText(f + bottomRadius));
    path.push("Q", numberText(f), numberText(h), numberText(f), numberText(h - bottomRadius));
    path.push("V", numberText(startY));
    path.push("Q", numberText(f), "0", numberText(topRadius), "0", "Z");

    return path.join(" ");
}

function dateOffset(date, days) {
    var result = new Date(date.getTime());
    result.setDate(result.getDate() + days);
    return result;
}

function monthCells(year, month) {
    var first = new Date(year, month, 1);
    var mondayOffset = (first.getDay() + 6) % 7;
    var start = dateOffset(first, -mondayOffset);
    var cells = [];
    var i;

    for (i = 0; i < 42; i += 1) {
        cells.push(dateOffset(start, i));
    }
    return cells;
}
