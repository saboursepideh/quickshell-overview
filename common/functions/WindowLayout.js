.pragma library

// Pure helpers for placing window previews inside a workspace cell.
// Rects are { key, x, y, width, height } in preview (cell-local) coordinates.

function normalizeMode(raw) {
    const mode = `${raw ?? "natural"}`.trim().toLowerCase();
    return (mode === "rows" || mode === "grid") ? mode : "natural";
}

// Ratio between a window's source monitor and the monitor showing the overview.
function geometryRatio(widgetMonitor, sourceMonitor) {
    if (!widgetMonitor || !sourceMonitor)
        return { x: 1, y: 1 };

    const rotated = monitor => (monitor.transform % 2 === 1);
    const widgetWidth = rotated(widgetMonitor) ? (widgetMonitor.height ?? 1) : (widgetMonitor.width ?? 1);
    const widgetHeight = rotated(widgetMonitor) ? (widgetMonitor.width ?? 1) : (widgetMonitor.height ?? 1);
    const sourceWidth = rotated(sourceMonitor) ? (sourceMonitor.height ?? 1) : (sourceMonitor.width ?? 1);
    const sourceHeight = rotated(sourceMonitor) ? (sourceMonitor.width ?? 1) : (sourceMonitor.height ?? 1);
    const sourceScale = sourceMonitor.scale ?? 1;
    const widgetScale = widgetMonitor.scale ?? 1;
    return {
        x: (widgetWidth * sourceScale) / (sourceWidth * widgetScale),
        y: (widgetHeight * sourceScale) / (sourceHeight * widgetScale)
    };
}

function hasOverlap(rects, tolerance) {
    const tol = Number.isFinite(tolerance) ? tolerance : 0;
    for (let i = 0; i < rects.length; i += 1) {
        const a = rects[i];
        for (let j = i + 1; j < rects.length; j += 1) {
            const b = rects[j];
            const overlapX = Math.min(a.x + a.width, b.x + b.width) - Math.max(a.x, b.x);
            const overlapY = Math.min(a.y + a.height, b.y + b.height) - Math.max(a.y, b.y);
            if (overlapX > tol && overlapY > tol)
                return true;
        }
    }
    return false;
}

function centerX(rect) {
    return rect.x + rect.width / 2;
}

function centerY(rect) {
    return rect.y + rect.height / 2;
}

// Split items (already sorted top-to-bottom) into `count` balanced rows, each sorted left-to-right.
function splitRows(items, count) {
    const rows = [];
    const base = Math.floor(items.length / count);
    const extra = items.length % count;
    let index = 0;
    for (let r = 0; r < count; r += 1) {
        const size = base + (r < extra ? 1 : 0);
        rows.push(items.slice(index, index + size).sort((a, b) => centerX(a) - centerX(b)));
        index += size;
    }
    return rows;
}

function layoutRows(items, innerW, innerH, gap) {
    let best = null;
    for (let rowCount = 1; rowCount <= items.length; rowCount += 1) {
        const rows = splitRows(items, rowCount);
        let scale = 1;
        let heightSum = 0;
        for (const row of rows) {
            const widthSum = row.reduce((sum, item) => sum + item.width, 0);
            scale = Math.min(scale, (innerW - gap * (row.length - 1)) / widthSum);
            heightSum += Math.max(...row.map(item => item.height));
        }
        scale = Math.min(scale, (innerH - gap * (rowCount - 1)) / heightSum);
        if (scale > 0 && (!best || scale > best.scale + 1e-9))
            best = { scale, rows, heightSum };
    }
    if (!best)
        return null;

    const slots = {};
    const scale = best.scale;
    const totalH = scale * best.heightSum + gap * (best.rows.length - 1);
    let y = (innerH - totalH) / 2;
    for (const row of best.rows) {
        const rowH = scale * Math.max(...row.map(item => item.height));
        const rowW = scale * row.reduce((sum, item) => sum + item.width, 0) + gap * (row.length - 1);
        let x = (innerW - rowW) / 2;
        for (const item of row) {
            const width = item.width * scale;
            const height = item.height * scale;
            slots[item.key] = { x, y: y + (rowH - height) / 2, width, height };
            x += width + gap;
        }
        y += rowH + gap;
    }
    return slots;
}

function fitScale(item, cellW, cellH) {
    return Math.min(1, cellW / item.width, cellH / item.height);
}

function layoutGrid(items, innerW, innerH, gap) {
    let best = null;
    for (let columns = 1; columns <= items.length; columns += 1) {
        const rowCount = Math.ceil(items.length / columns);
        const cellW = (innerW - gap * (columns - 1)) / columns;
        const cellH = (innerH - gap * (rowCount - 1)) / rowCount;
        if (cellW <= 0 || cellH <= 0)
            continue;
        const area = items.reduce((sum, item) => {
            const s = fitScale(item, cellW, cellH);
            return sum + item.width * item.height * s * s;
        }, 0);
        if (!best || area > best.area + 1e-9)
            best = { area, columns, rowCount, cellW, cellH };
    }
    if (!best)
        return null;

    const slots = {};
    const { columns, rowCount, cellW, cellH } = best;
    for (let r = 0; r < rowCount; r += 1) {
        const row = items.slice(r * columns, (r + 1) * columns).sort((a, b) => centerX(a) - centerX(b));
        const rowOffset = (columns - row.length) * (cellW + gap) / 2;
        row.forEach((item, c) => {
            const s = fitScale(item, cellW, cellH);
            const width = item.width * s;
            const height = item.height * s;
            slots[item.key] = {
                x: rowOffset + c * (cellW + gap) + (cellW - width) / 2,
                y: r * (cellH + gap) + (cellH - height) / 2,
                width,
                height
            };
        });
    }
    return slots;
}

// Returns { key: { x, y, width, height } } spreading rects inside areaW x areaH without overlap.
// Previews keep their aspect ratio and are never enlarged beyond their natural size.
function computeSlots(rects, areaW, areaH, mode, gap) {
    const items = rects.filter(rect => rect.width > 0 && rect.height > 0);
    const padding = Math.max(0, gap);
    const innerW = areaW - padding * 2;
    const innerH = areaH - padding * 2;
    if (items.length === 0 || innerW <= 0 || innerH <= 0)
        return {};

    items.sort((a, b) => (centerY(a) - centerY(b)) || (centerX(a) - centerX(b)));
    const slots = mode === "grid" ? layoutGrid(items, innerW, innerH, padding) : layoutRows(items, innerW, innerH, padding);
    if (!slots)
        return {};

    for (const key in slots) {
        slots[key].x += padding;
        slots[key].y += padding;
    }
    return slots;
}
