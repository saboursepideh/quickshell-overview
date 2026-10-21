import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../common"
import "../../common/functions"
import "../../common/functions/WindowLayout.js" as WindowLayout
import "../../common/widgets"
import "../../services"
import "."

Item {
    id: root
    required property var panelWindow
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
    readonly property var toplevels: ToplevelManager.toplevels
    readonly property int effectiveActiveWorkspaceId: Math.max(1, Math.min(100, monitor?.activeWorkspace?.id ?? 1))
    readonly property int workspacesShown: Config.options.overview.rows * Config.options.overview.columns
    readonly property bool useWorkspaceMap: Config.options.overview.useWorkspaceMap
    readonly property var workspaceMap: Config.options.overview.workspaceMap
    readonly property int workspaceOffset: useWorkspaceMap ? Number(workspaceMap[root.monitor?.id] ?? 0) : 0
    readonly property int workspaceGroup: Math.floor((effectiveActiveWorkspaceId - workspaceOffset - 1) / workspacesShown)
    property bool monitorIsFocused: (Hyprland.focusedMonitor?.name == monitor.name)
    property var windows: HyprlandData.windowList
    property var windowByAddress: HyprlandData.windowByAddress
    property var windowAddresses: HyprlandData.addresses
    property var workspaceIds: HyprlandData.workspaceIds
    property var monitorData: HyprlandData.monitors.find(m => m.id === root.monitor?.id)
    property real scale: Config.options.overview.scale
    property color activeBorderColor: Appearance.colors.colSecondary

    readonly property real monitorUsableWidth: (monitorData?.transform % 2 === 1) ?
        (monitor.height / monitor.scale - (monitorData?.reserved?.[0] ?? 0) - (monitorData?.reserved?.[2] ?? 0)) :
        (monitor.width / monitor.scale - (monitorData?.reserved?.[0] ?? 0) - (monitorData?.reserved?.[2] ?? 0))
    readonly property real monitorUsableHeight: (monitorData?.transform % 2 === 1) ?
        (monitor.width / monitor.scale - (monitorData?.reserved?.[1] ?? 0) - (monitorData?.reserved?.[3] ?? 0)) :
        (monitor.height / monitor.scale - (monitorData?.reserved?.[1] ?? 0) - (monitorData?.reserved?.[3] ?? 0))
    property real workspaceImplicitWidth: Math.round(monitorUsableWidth * root.scale)
    property real workspaceImplicitHeight: Math.round(monitorUsableHeight * root.scale)

    property real workspaceNumberMargin: 80
    property real workspaceNumberSize: Config.options.overview.workspaceNumberBaseSize * monitor.scale
    property int workspaceZ: 0
    property int windowZ: 1
    property int windowDraggingZ: 99999
    property real workspaceSpacing: Config.options.overview.workspaceSpacing
    readonly property string windowLayoutMode: WindowLayout.normalizeMode(Config.options.overview.windowLayout)
    readonly property real windowLayoutGap: Math.max(2, workspaceSpacing)
    property string emptyWorkspaceWallpaperPath: Config.options.overview.emptyWorkspaceWallpaper
    property string specialEmptyWorkspaceWallpaperPath: Config.options.overview.specialEmptyWorkspaceWallpaper
    property bool showSpecialWorkspaces: Config.options.overview.showSpecialWorkspaces
    property var configuredSpecialWorkspaces: Config.options.overview.specialWorkspaces ?? []
    property int specialWorkspaceColumns: Math.max(1, Config.options.overview.specialWorkspaceColumns)
    property real panelOpacity: Math.max(0, Math.min(1, Config.options.overview.effects.panelOpacity))
    property real workspaceOpacity: Math.max(0, Math.min(1, Config.options.overview.effects.workspaceOpacity))
    property real emptyWorkspaceWallpaperOverlayOpacity: Math.max(0, Math.min(1, Config.options.overview.effects.emptyWorkspaceWallpaperOverlayOpacity))
    property bool glassMode: Config.options.overview.effects.glassMode
    property real glassTintStrength: Math.max(0, Math.min(1, Config.options.overview.effects.glassTintStrength))
    property real glassBorderOpacity: Math.max(0, Math.min(1, Config.options.overview.effects.glassBorderOpacity))
    property real glassShineOpacity: Math.max(0, Math.min(1, Config.options.overview.effects.glassShineOpacity))
    property real effectivePanelOpacity: glassMode ? Math.min(panelOpacity, 0.72) : panelOpacity
    property real effectiveWorkspaceOpacity: glassMode ? Math.min(workspaceOpacity, 0.62) : workspaceOpacity

    property int draggingFromWorkspace: -1
    property int draggingTargetWorkspace: -1
    property string draggingTargetSpecialWorkspace: ""
    property int previewRecaptureToken: 0
    property var allWorkspaces: HyprlandData.allWorkspaces
    property bool previewsEnabled: Config.options.overview.previewsEnabled
    property string previewModeRaw: Config.options.overview.previewMode
    property string previewMode: {
        const mode = `${previewModeRaw ?? "live"}`.trim().toLowerCase();
        return (mode === "event" || mode === "snapshot") ? "event" : "live";
    }
    property bool useEventPreviewRefresh: previewsEnabled && previewMode === "event"

    readonly property var monitorSpecialWorkspaceNames: {
        const names = [];
        for (const ws of (allWorkspaces ?? [])) {
            const name = `${ws?.name ?? ""}`;
            if (!name.startsWith("special:"))
                continue;
            if (`${ws?.monitor ?? ""}` !== `${root.monitor?.name ?? ""}`)
                continue;
            names.push(name.slice(8));
        }
        return names;
    }

    readonly property var specialWorkspaceNamesFromWindows: {
        const names = [];
        for (const addr in windowByAddress) {
            const win = windowByAddress[addr];
            if ((win?.monitor ?? -1) !== (root.monitor?.id ?? -1))
                continue;
            const wsName = `${win?.workspace?.name ?? ""}`;
            if (!wsName.startsWith("special:"))
                continue;
            names.push(wsName.slice(8));
        }
        return names;
    }

    readonly property var visibleSpecialWorkspaces: {
        if (!showSpecialWorkspaces)
            return [];

        const out = [];
        const pushUnique = (value) => {
            const cleaned = `${value ?? ""}`.trim();
            if (cleaned.length === 0 || out.includes(cleaned))
                return;
            out.push(cleaned);
        };

        for (const configured of configuredSpecialWorkspaces ?? [])
            pushUnique(configured);
        for (const name of monitorSpecialWorkspaceNames)
            pushUnique(name);
        for (const name of specialWorkspaceNamesFromWindows)
            pushUnique(name);

        return out;
    }

    readonly property bool hasSpecialWorkspaceSection: visibleSpecialWorkspaces.length > 0
    readonly property bool hasEmptyWorkspaceWallpaper: `${emptyWorkspaceWallpaperPath ?? ""}`.trim().length > 0
    readonly property bool hasSpecialEmptyWorkspaceWallpaper: `${specialEmptyWorkspaceWallpaperPath ?? ""}`.trim().length > 0
    readonly property string createSpecialWorkspaceTarget: "__create_special_workspace__"
    readonly property real specialWorkspaceTileHeight: root.workspaceImplicitHeight
    readonly property real specialStripGap: workspaceSpacing * 1.8
    readonly property real specialStripPadding: Math.max(8, 12 * root.scale)
    readonly property real specialStripTitleHeight: Math.max(14, Appearance.font.pixelSize.small * root.scale)
    readonly property real specialStripTitleGap: Math.max(6, 8 * root.scale)
    readonly property int totalSpecialTiles: visibleSpecialWorkspaces.length + 1
    readonly property real specialSectionWidth: root.workspaceAreaWidth
    readonly property real specialGridInnerWidth: Math.max(0, root.specialSectionWidth - root.specialStripPadding * 2)
    readonly property int effectiveSpecialColumns: Math.max(1, Math.min(root.specialWorkspaceColumns, root.totalSpecialTiles))
    readonly property int specialWorkspaceRows: Math.ceil(root.totalSpecialTiles / root.effectiveSpecialColumns)
    readonly property real specialWorkspaceAspectCap: {
        let maxAspect = Math.max(1, root.workspaceImplicitWidth / Math.max(1, root.workspaceImplicitHeight));
        for (const name of visibleSpecialWorkspaces) {
            const geometry = root.specialWorkspaceGeometry(name, root.monitor?.id);
            const width = geometry?.width;
            const height = geometry?.height;
            if (!Number.isFinite(width) || !Number.isFinite(height) || height <= 0)
                continue;
            maxAspect = Math.max(maxAspect, width / height);
        }
        return maxAspect;
    }
    readonly property real specialWorkspaceTileWidth: {
        const gaps = Math.max(0, root.effectiveSpecialColumns - 1);
        const rawWidth = (root.specialGridInnerWidth - gaps * workspaceSpacing) / root.effectiveSpecialColumns;
        const aspectWidth = root.specialWorkspaceTileHeight * root.specialWorkspaceAspectCap;
        const cappedWidth = Math.min(rawWidth, aspectWidth);
        return Math.max(80 * root.scale, cappedWidth);
    }
    readonly property real specialGridUsedWidth: root.effectiveSpecialColumns * root.specialWorkspaceTileWidth + Math.max(0, root.effectiveSpecialColumns - 1) * workspaceSpacing
    readonly property real specialGridOffsetX: root.specialStripPadding + Math.max(0, (root.specialGridInnerWidth - root.specialGridUsedWidth) / 2)
    readonly property real specialStripTop: root.workspaceAreaHeight + workspaceSpacing + root.specialStripGap
    readonly property real specialStripTilesTop: root.specialStripTop + root.specialStripPadding + root.specialStripTitleHeight + root.specialStripTitleGap
    readonly property real specialGridHeight: root.specialWorkspaceRows * root.specialWorkspaceTileHeight + Math.max(0, root.specialWorkspaceRows - 1) * workspaceSpacing
    readonly property real specialStripHeight: root.specialStripPadding * 2 + root.specialStripTitleHeight + root.specialStripTitleGap + root.specialGridHeight

    function getWorkspaceRow(workspaceId) {
        if (!Number.isFinite(workspaceId))
            return 0;
        const adjusted = workspaceId - workspaceOffset;
        const normalRow = Math.floor((adjusted - 1) / Config.options.overview.columns) % Config.options.overview.rows;
        return Config.options.overview.orderBottomUp ? (Config.options.overview.rows - normalRow - 1) : normalRow;
    }

    function getWorkspaceColumn(workspaceId) {
        if (!Number.isFinite(workspaceId))
            return 0;
        const adjusted = workspaceId - workspaceOffset;
        const normalCol = (adjusted - 1) % Config.options.overview.columns;
        return Config.options.overview.orderRightLeft ? (Config.options.overview.columns - normalCol - 1) : normalCol;
    }

    function getWorkspaceInCell(rowIndex, colIndex) {
        const mappedRow = Config.options.overview.orderBottomUp ? (Config.options.overview.rows - rowIndex - 1) : rowIndex;
        const mappedCol = Config.options.overview.orderRightLeft ? (Config.options.overview.columns - colIndex - 1) : colIndex;
        return (workspaceGroup * workspacesShown) + (mappedRow * Config.options.overview.columns) + mappedCol + 1 + workspaceOffset;
    }

    readonly property bool focusLayout: `${Config.options.overview.workspaceLayout ?? "grid"}`.trim().toLowerCase() === "focus"
    readonly property real focusSize: Math.max(0.1, Math.min(1, Config.options.overview.focusSize))
    readonly property string scrollSwitch: `${Config.options.overview.scrollSwitch ?? "continuous"}`.trim().toLowerCase()
    readonly property var emptyWorkspaceCell: ({ x: 0, y: 0, width: 0, height: 0, scale: 0 })

    function isWorkspaceRowShown(workspaceId) {
        return !Config.options.overview.hideEmptyRows || !(rowsWithContent instanceof Set)
            || rowsWithContent.has(getWorkspaceRow(workspaceId));
    }

    readonly property var shownWorkspaceIds: {
        const ids = [];
        for (let row = 0; row < Config.options.overview.rows; row += 1) {
            for (let col = 0; col < Config.options.overview.columns; col += 1) {
                const id = getWorkspaceInCell(row, col);
                if (isWorkspaceRowShown(id))
                    ids.push(id);
            }
        }
        return ids;
    }

    readonly property var focusLayoutCells: {
        if (!root.focusLayout)
            return ({ cells: {}, width: 0, height: 0 });
        const screenWidth = root.panelWindow?.width || root.monitorUsableWidth;
        const screenHeight = root.panelWindow?.height || root.monitorUsableHeight;
        const chrome = (Appearance.sizes.elevationMargin + Config.options.overview.backgroundPadding) * 2;
        const specialHeight = root.showSpecialWorkspaces ? (workspaceSpacing * 2 + root.specialStripGap + root.specialStripHeight) : 0;
        const areaWidth = screenWidth - chrome - Appearance.sizes.elevationMargin * 2;
        const areaHeight = screenHeight - Config.options.position.topMargin - chrome - Appearance.sizes.elevationMargin - specialHeight;
        return WindowLayout.focusCells(root.shownWorkspaceIds, root.effectiveActiveWorkspaceId,
            root.monitorUsableWidth, root.monitorUsableHeight, screenWidth * root.focusSize,
            areaWidth, areaHeight, workspaceSpacing);
    }

    readonly property real workspaceAreaWidth: root.focusLayout ? root.focusLayoutCells.width
        : Config.options.overview.columns * (root.workspaceImplicitWidth + workspaceSpacing) - workspaceSpacing
    readonly property real workspaceAreaHeight: {
        if (root.focusLayout)
            return root.focusLayoutCells.height;
        const rows = (Config.options.overview.hideEmptyRows && rowsWithContent instanceof Set) ? rowsWithContent.size : Config.options.overview.rows;
        return Math.max(0, rows * (root.workspaceImplicitHeight + workspaceSpacing) - workspaceSpacing);
    }

    // { x, y, width, height, scale } of a regular workspace inside the workspace area.
    function workspaceCell(workspaceId) {
        if (root.focusLayout)
            return root.focusLayoutCells.cells[workspaceId] ?? root.emptyWorkspaceCell;
        return {
            x: (root.workspaceImplicitWidth + workspaceSpacing) * getWorkspaceColumn(workspaceId),
            y: (root.workspaceImplicitHeight + workspaceSpacing) * getVisibleRowPosition(getWorkspaceRow(workspaceId)),
            width: root.workspaceImplicitWidth,
            height: root.workspaceImplicitHeight,
            scale: root.scale
        };
    }

    function getVisibleRowPosition(rowIndex) {
        if (!Number.isFinite(rowIndex) || rowIndex < 0)
            return 0;
        if (!Config.options.overview.hideEmptyRows || !(rowsWithContent instanceof Set))
            return rowIndex;

        let visibleRow = 0;
        for (let i = 0; i < rowIndex; i += 1) {
            if (rowsWithContent.has(i))
                visibleRow += 1;
        }
        return visibleRow;
    }

    function stepWorkspace(delta) {
        if (!Number.isFinite(delta) || delta === 0)
            return;

        const currentId = monitor?.activeWorkspace?.id ?? effectiveActiveWorkspaceId;
        const minWorkspaceId = workspaceOffset + 1;
        let maxWorkspaceId = minWorkspaceId + workspacesShown - 1;
        for (const workspaceId of (workspaceIds ?? [])) {
            if (Number.isFinite(workspaceId) && workspaceId >= minWorkspaceId) {
                maxWorkspaceId = Math.max(maxWorkspaceId, workspaceId);
            }
        }
        maxWorkspaceId = Math.max(maxWorkspaceId, currentId);

        let targetId = currentId + delta;
        if (targetId < minWorkspaceId) {
            targetId = maxWorkspaceId;
        } else if (targetId > maxWorkspaceId) {
            targetId = minWorkspaceId;
        }
        if (Hyprland.usingLua) {
            Hyprland.dispatch(`hl.dsp.focus({workspace = '${targetId}'})`);
        } else {
            Hyprland.dispatch(`workspace ${targetId}`);
        }
    }

    function isSpecialWorkspace(windowData) {
        const wsName = `${windowData?.workspace?.name ?? ""}`;
        return wsName.startsWith("special:");
    }

    function specialWorkspaceName(windowData) {
        const wsName = `${windowData?.workspace?.name ?? ""}`;
        return wsName.startsWith("special:") ? wsName.slice(8) : "";
    }

    function specialWorkspaceIndex(name) {
        return visibleSpecialWorkspaces.indexOf(`${name ?? ""}`);
    }

    function specialWorkspaceLabel(name) {
        const raw = `${name ?? ""}`.trim();
        if (raw.length === 0)
            return "Special";
        return raw.replace(/[-_]+/g, " ");
    }

    function nextSpecialWorkspaceName() {
        const taken = new Set();
        for (const name of visibleSpecialWorkspaces)
            taken.add(`${name ?? ""}`.trim().toLowerCase());

        const base = "stash";
        if (!taken.has(base))
            return base;

        let index = 2;
        while (taken.has(`${base}-${index}`))
            index += 1;

        return `${base}-${index}`;
    }

    function wallpaperSource(path) {
        const trimmed = `${path ?? ""}`.trim();
        if (trimmed.length === 0)
            return "";
        if (trimmed.startsWith("file:/") || trimmed.startsWith("qrc:/") || trimmed.startsWith("image://") || trimmed.startsWith("http://") || trimmed.startsWith("https://"))
            return trimmed;
        if (trimmed.startsWith("/"))
            return `file://${trimmed}`;
        return trimmed;
    }

    function workspaceHasWindows(workspaceId) {
        if (!Number.isFinite(workspaceId))
            return false;

        for (const addr in windowByAddress) {
            const win = windowByAddress[addr];
            if (root.isSpecialWorkspace(win))
                continue;
            if ((win?.workspace?.id ?? -1) === workspaceId)
                return true;
        }
        return false;
    }

    function specialWindowZ(win) {
        const pinned = win?.pinned ? 200000 : 0;
        const floating = win?.floating ? 100000 : 0;
        const focus = 10000 - (win?.focusHistoryID ?? 9999);
        return pinned + floating + focus;
    }

    function specialWorkspaceGeometry(name, monitorId) {
        const trimmedName = `${name ?? ""}`.trim();
        const currentMonitorId = monitorId ?? -1;
        let minX = null;
        let minY = null;
        let maxX = null;
        let maxY = null;

        for (const addr in windowByAddress) {
            const win = windowByAddress[addr];
            if ((win?.monitor ?? -1) !== currentMonitorId)
                continue;
            if (root.specialWorkspaceName(win) !== trimmedName)
                continue;

            const atX = win?.at?.[0];
            const atY = win?.at?.[1];
            const width = win?.size?.[0];
            const height = win?.size?.[1];
            if (!Number.isFinite(atX) || !Number.isFinite(atY))
                continue;
            if (!Number.isFinite(width) || !Number.isFinite(height))
                continue;

            minX = minX === null ? atX : Math.min(minX, atX);
            minY = minY === null ? atY : Math.min(minY, atY);
            maxX = maxX === null ? (atX + width) : Math.max(maxX, atX + width);
            maxY = maxY === null ? (atY + height) : Math.max(maxY, atY + height);
        }

        return {
            x: minX,
            y: minY,
            width: (minX !== null && maxX !== null) ? Math.max(1, maxX - minX) : null,
            height: (minY !== null && maxY !== null) ? Math.max(1, maxY - minY) : null
        };
    }

    function toplevelAddressSet() {
        return new Set(ToplevelManager.toplevels.values.map(toplevel => `0x${toplevel.HyprlandToplevel.address}`));
    }

    // Spread-layout slots for one group of windows, or null when the natural layout should be kept.
    function spreadSlots(rects, areaW, areaH) {
        if (rects.length < 2 || !WindowLayout.hasOverlap(rects, 1))
            return null;
        return WindowLayout.computeSlots(rects, areaW, areaH, root.windowLayoutMode, root.windowLayoutGap);
    }

    // Address -> cell-local slot for windows in overlapping regular workspaces of the current group.
    property var workspaceLayoutSlots: {
        if (root.windowLayoutMode === "natural")
            return ({});

        const firstWorkspace = root.workspaceGroup * root.workspacesShown + 1 + workspaceOffset;
        const lastWorkspace = (root.workspaceGroup + 1) * root.workspacesShown + workspaceOffset;
        const addresses = root.toplevelAddressSet();
        const groups = {};
        for (const addr in windowByAddress) {
            const win = windowByAddress[addr];
            const wsId = win?.workspace?.id;
            if (!addresses.has(addr) || root.isSpecialWorkspace(win) || !(wsId >= firstWorkspace && wsId <= lastWorkspace))
                continue;
            if (!groups[wsId])
                groups[wsId] = [];
            groups[wsId].push(win);
        }

        const slots = {};
        for (const wsId in groups) {
            const cell = root.workspaceCell(Number(wsId));
            if (!(cell.width > 0 && cell.height > 0))
                continue;
            const rects = groups[wsId].map(win => {
                const monitor = HyprlandData.monitors.find(m => m.id === win?.monitor);
                const ratio = WindowLayout.geometryRatio(root.monitorData, monitor);
                const baseX = (monitor?.x ?? 0) + (monitor?.reserved?.[0] ?? 0);
                const baseY = (monitor?.y ?? 0) + (monitor?.reserved?.[1] ?? 0);
                return {
                    key: win.address,
                    x: Math.max(((win?.at?.[0] ?? 0) - baseX) * cell.scale * ratio.x, 0),
                    y: Math.max(((win?.at?.[1] ?? 0) - baseY) * cell.scale * ratio.y, 0),
                    width: Math.min((win?.size?.[0] ?? 100) * cell.scale * ratio.x, cell.width),
                    height: Math.min((win?.size?.[1] ?? 100) * cell.scale * ratio.y, cell.height)
                };
            });
            Object.assign(slots, root.spreadSlots(rects, cell.width, cell.height) ?? {});
        }
        return slots;
    }

    // Calculate which rows have windows or current workspace
    property var rowsWithContent: {
        if (!Config.options.overview.hideEmptyRows) return null;

        let rows = new Set();
        const firstWorkspace = root.workspaceGroup * root.workspacesShown + 1 + workspaceOffset;
        const lastWorkspace = (root.workspaceGroup + 1) * root.workspacesShown + workspaceOffset;

        // Add row containing current workspace
        const currentWorkspace = effectiveActiveWorkspaceId;
        if (currentWorkspace >= firstWorkspace && currentWorkspace <= lastWorkspace) {
            rows.add(getWorkspaceRow(currentWorkspace));
        }

        // Add rows with windows
        for (let addr in windowByAddress) {
            const win = windowByAddress[addr];
            const wsId = win?.workspace?.id;
            if (wsId >= firstWorkspace && wsId <= lastWorkspace) {
                const rowIndex = getWorkspaceRow(wsId);
                rows.add(rowIndex);
            }
        }

        return rows;
    }

    implicitWidth: overviewBackground.implicitWidth + Appearance.sizes.elevationMargin * 2
    implicitHeight: overviewBackground.implicitHeight + Appearance.sizes.elevationMargin * 2

    property Component windowComponent: OverviewWindow {}
    property list<OverviewWindow> windowWidgets: []

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (!GlobalStates.overviewOpen || !root.useEventPreviewRefresh)
                return;

            const eventName = `${event?.name ?? event?.event ?? event?.type ?? ""}`;
            if (eventName === "closewindow" || eventName === "openwindow" || eventName === "movewindow") {
                root.previewRecaptureToken += 1;
            }
        }
    }

    StyledRectangularShadow {
        target: overviewBackground
    }
    Rectangle { // Background
        id: overviewBackground
        property real padding: Config.options.overview.backgroundPadding
        anchors.fill: parent
        anchors.margins: Appearance.sizes.elevationMargin

        implicitWidth: contentLayout.implicitWidth + padding * 2
        implicitHeight: contentLayout.implicitHeight + padding * 2
        radius: Appearance.rounding.screenRounding * root.scale + (Appearance.rounding.screenRounding !== 0 ? padding : 0)
        clip: true
        color: ColorUtils.applyAlpha(
            root.glassMode
                ? ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.78 - root.glassTintStrength * 0.35)
                : Appearance.colors.colLayer0,
            root.effectivePanelOpacity
        )
        border.width: 1
        border.color: ColorUtils.applyAlpha(
            root.glassMode
                ? ColorUtils.mix(Appearance.colors.colLayer0Border, Appearance.m3colors.m3outline, 0.52)
                : Appearance.colors.colLayer0Border,
            root.glassMode ? root.glassBorderOpacity : root.effectivePanelOpacity
        )

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onPressed: mouse => mouse.accepted = true
        }

        Rectangle {
            visible: root.glassMode
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            gradient: Gradient {
                GradientStop { position: 0.0; color: ColorUtils.applyAlpha("#FFFFFF", root.glassShineOpacity * 0.35) }
                GradientStop { position: 0.42; color: ColorUtils.applyAlpha("#FFFFFF", 0.0) }
                GradientStop { position: 1.0; color: ColorUtils.applyAlpha("#000000", root.glassShineOpacity * 0.22) }
            }
        }

        Rectangle {
            visible: root.glassMode
            anchors.fill: parent
            anchors.margins: 1
            radius: Math.max(parent.radius - 1, 0)
            color: "transparent"
            border.width: 1
            border.color: ColorUtils.applyAlpha("#FFFFFF", root.glassBorderOpacity * 0.20)
        }

        ColumnLayout { // Workspaces
            id: contentLayout

            z: root.workspaceZ
            anchors.centerIn: parent
            spacing: workspaceSpacing
            Item {
                id: workspaceArea
                implicitWidth: root.workspaceAreaWidth
                implicitHeight: root.workspaceAreaHeight

                Repeater { // Workspace repeater
                    model: root.workspacesShown
                    Rectangle { // Workspace
                        id: workspace
                        property int rowIndex: Math.floor(index / Config.options.overview.columns)
                        property int colIndex: index % Config.options.overview.columns
                        property int workspaceValue: root.getWorkspaceInCell(rowIndex, colIndex)
                        property bool showWallpaper: root.hasEmptyWorkspaceWallpaper
                        property color defaultWorkspaceColor: Appearance.colors.colLayer1
                        property color hoveredWorkspaceColor: ColorUtils.mix(defaultWorkspaceColor, Appearance.colors.colLayer1Hover, 0.1)
                        property color hoveredBorderColor: Appearance.colors.colLayer2Hover
                        property bool hoveredWhileDragging: false
                        property var cell: root.workspaceCell(workspaceValue)

                        visible: root.isWorkspaceRowShown(workspaceValue) && cell.width > 0
                        x: cell.x
                        y: cell.y
                        width: cell.width
                        height: cell.height
                        Behavior on x {
                            enabled: root.focusLayout
                            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                        }
                        Behavior on y {
                            enabled: root.focusLayout
                            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                        }
                        Behavior on width {
                            enabled: root.focusLayout
                            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                        }
                        Behavior on height {
                            enabled: root.focusLayout
                            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                        }
                        color: showWallpaper ? "transparent" : ColorUtils.applyAlpha(
                            root.glassMode
                                ? ColorUtils.mix(hoveredWhileDragging ? hoveredWorkspaceColor : defaultWorkspaceColor, Appearance.colors.colLayer0, 0.46)
                                : (hoveredWhileDragging ? hoveredWorkspaceColor : defaultWorkspaceColor),
                            root.effectiveWorkspaceOpacity
                        )
                        radius: Appearance.rounding.screenRounding * cell.scale
                        border.width: 2
                        border.color: hoveredWhileDragging
                            ? ColorUtils.applyAlpha(hoveredBorderColor, root.glassMode ? root.glassBorderOpacity : 1)
                            : "transparent"

                        Image {
                            id: workspaceWallpaper
                            visible: workspace.showWallpaper
                            anchors.fill: parent
                            source: root.wallpaperSource(root.emptyWorkspaceWallpaperPath)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            smooth: true
                            mipmap: true
                            layer.enabled: workspace.showWallpaper
                            layer.smooth: true
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: workspaceWallpaperMask
                                maskThresholdMin: 0.5
                                maskSpreadAtMin: 1.0
                            }
                        }

                        Item {
                            id: workspaceWallpaperMask
                            anchors.fill: parent
                            visible: false
                            layer.enabled: true
                            layer.smooth: true
                            Rectangle {
                                anchors.fill: parent
                                radius: workspace.radius
                            }
                        }

                        Rectangle {
                            visible: workspace.showWallpaper
                            anchors.fill: parent
                            radius: parent.radius
                            color: ColorUtils.applyAlpha(
                                root.glassMode
                                    ? ColorUtils.mix(workspace.hoveredWhileDragging ? workspace.hoveredWorkspaceColor : workspace.defaultWorkspaceColor, Appearance.colors.colLayer0, 0.40)
                                    : (workspace.hoveredWhileDragging ? workspace.hoveredWorkspaceColor : workspace.defaultWorkspaceColor),
                                workspace.hoveredWhileDragging
                                    ? Math.min(0.28, root.emptyWorkspaceWallpaperOverlayOpacity + 0.08)
                                    : root.emptyWorkspaceWallpaperOverlayOpacity
                            )
                        }

                        Rectangle {
                            visible: root.glassMode
                            anchors.fill: parent
                            radius: parent.radius
                            color: "transparent"
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: ColorUtils.applyAlpha("#FFFFFF", root.glassShineOpacity * 0.22) }
                                GradientStop { position: 0.46; color: ColorUtils.applyAlpha("#FFFFFF", 0.0) }
                                GradientStop { position: 1.0; color: ColorUtils.applyAlpha("#000000", root.glassShineOpacity * 0.14) }
                            }
                        }

                        Rectangle {
                            visible: root.glassMode
                            anchors.fill: parent
                            anchors.margins: 1
                            radius: Math.max(parent.radius - 1, 0)
                            color: "transparent"
                            border.width: 1
                            border.color: ColorUtils.applyAlpha("#FFFFFF", root.glassBorderOpacity * 0.16)
                        }

                        StyledText {
                            anchors.centerIn: parent
                            visible: !workspace.showWallpaper
                            text: workspaceValue
                            font {
                                pixelSize: root.workspaceNumberSize * workspace.cell.scale
                                weight: Font.DemiBold
                                family: Appearance.font.family.expressive
                            }
                            color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.8)
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        MouseArea {
                            id: workspaceArea
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            onClicked: {
                                if (root.draggingTargetWorkspace === -1) {
                                    GlobalStates.overviewOpen = false
                                    if (Hyprland.usingLua) {
                                        Hyprland.dispatch(`hl.dsp.focus({workspace = '${workspaceValue}'})`);
                                    } else {
                                        Hyprland.dispatch(`workspace ${workspaceValue}`)
                                    }
                                }
                            }
                        }

                        DropArea {
                            anchors.fill: parent
                            onEntered: {
                                root.draggingTargetWorkspace = workspaceValue
                                root.draggingTargetSpecialWorkspace = ""
                                if (root.draggingFromWorkspace == root.draggingTargetWorkspace) return;
                                hoveredWhileDragging = true
                            }
                            onExited: {
                                hoveredWhileDragging = false
                                if (root.draggingTargetWorkspace == workspaceValue) root.draggingTargetWorkspace = -1
                            }
                        }

                    }
                }
            }

            Item {
                visible: root.showSpecialWorkspaces
                implicitWidth: 1
                implicitHeight: root.specialStripGap
            }

            Item {
                id: specialWorkspaceSection
                visible: root.showSpecialWorkspaces
                implicitWidth: root.specialSectionWidth
                implicitHeight: root.specialStripHeight

                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.normal * root.scale
                    color: ColorUtils.applyAlpha(
                        root.glassMode
                            ? ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.70)
                            : Appearance.colors.colLayer1,
                        root.glassMode ? Math.min(0.74, root.effectivePanelOpacity) : root.effectiveWorkspaceOpacity
                    )
                    border.width: 1
                    border.color: ColorUtils.applyAlpha(Appearance.colors.colLayer2Border, root.glassMode ? root.glassBorderOpacity : 0.65)

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: Math.max(18 * root.scale, root.specialStripPadding + root.specialStripTitleHeight * 0.8)
                        radius: parent.radius
                        color: ColorUtils.applyAlpha(Appearance.colors.colSecondary, root.glassMode ? 0.12 : 0.08)
                    }

                    StyledText {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.leftMargin: root.specialStripPadding
                        anchors.topMargin: root.specialStripPadding
                        text: "Special Workspaces"
                        font.family: Appearance.font.family.title
                        font.pixelSize: root.specialStripTitleHeight
                        font.weight: Font.DemiBold
                        color: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.84)
                    }

                    Grid {
                        id: specialWorkspaceGrid
                        x: root.specialGridOffsetX
                        y: root.specialStripPadding + root.specialStripTitleHeight + root.specialStripTitleGap
                        width: root.specialGridUsedWidth
                        columns: root.effectiveSpecialColumns
                        rowSpacing: workspaceSpacing
                        columnSpacing: workspaceSpacing

                        Repeater {
                            model: root.visibleSpecialWorkspaces
                            delegate: Rectangle {
                                id: specialWorkspaceTile
                                required property string modelData
                                property string specialName: modelData
                                property var specialGeometry: root.specialWorkspaceGeometry(specialName, root.monitor?.id)
                                property color baseColor: ColorUtils.mix(Appearance.colors.colLayer1, Appearance.colors.colLayer0, 0.52)
                                property bool hasRenderableGeometry: Number.isFinite(specialGeometry?.width)
                                    && Number.isFinite(specialGeometry?.height)
                                    && specialGeometry.width > 0
                                    && specialGeometry.height > 0
                                property bool showWallpaper: root.hasSpecialEmptyWorkspaceWallpaper
                                property real geometryWidth: hasRenderableGeometry ? specialGeometry.width : Math.max(1, root.workspaceImplicitWidth / root.scale)
                                property real geometryHeight: hasRenderableGeometry ? specialGeometry.height : Math.max(1, root.workspaceImplicitHeight / root.scale)
                                property real fitScale: hasRenderableGeometry ? Math.min(width / geometryWidth, height / geometryHeight) : root.scale
                                property real contentWidth: hasRenderableGeometry ? (geometryWidth * fitScale) : width
                                property real contentHeight: hasRenderableGeometry ? (geometryHeight * fitScale) : height
                                property real contentOffsetX: Math.max(0, (width - contentWidth) / 2)
                                property real contentOffsetY: Math.max(0, (height - contentHeight) / 2)
                                // Address -> tile-local slot when this tile's windows overlap and a spread layout is enabled.
                                property var layoutSlots: {
                                    if (root.windowLayoutMode === "natural" || !hasRenderableGeometry)
                                        return null;
                                    const addresses = root.toplevelAddressSet();
                                    const rects = [];
                                    for (const addr in windowByAddress) {
                                        const win = windowByAddress[addr];
                                        if (!addresses.has(addr) || (win?.monitor ?? -1) !== (root.monitor?.id ?? -1) || root.specialWorkspaceName(win) !== specialName)
                                            continue;
                                        rects.push({
                                            key: win.address,
                                            x: ((win?.at?.[0] ?? 0) - specialGeometry.x) * fitScale,
                                            y: ((win?.at?.[1] ?? 0) - specialGeometry.y) * fitScale,
                                            width: (win?.size?.[0] ?? 100) * fitScale,
                                            height: (win?.size?.[1] ?? 100) * fitScale
                                        });
                                    }
                                    return root.spreadSlots(rects, width, height);
                                }
                                property bool spread: layoutSlots !== null
                                implicitWidth: root.specialWorkspaceTileWidth
                                implicitHeight: root.specialWorkspaceTileHeight
                                radius: Appearance.rounding.screenRounding * root.scale
                                clip: true
                                color: showWallpaper ? "transparent" : ColorUtils.applyAlpha(
                                    root.glassMode
                                        ? ColorUtils.mix(baseColor, Appearance.colors.colLayer0, 0.44)
                                        : baseColor,
                                    root.effectiveWorkspaceOpacity
                                )
                                border.width: 1
                                border.color: ColorUtils.applyAlpha(Appearance.colors.colLayer2Border, root.glassMode ? root.glassBorderOpacity : 0.75)

                                Image {
                                    visible: specialWorkspaceTile.showWallpaper
                                    anchors.fill: parent
                                    source: root.wallpaperSource(root.specialEmptyWorkspaceWallpaperPath)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    smooth: true
                                    mipmap: true
                                }

                                Rectangle {
                                    visible: specialWorkspaceTile.showWallpaper
                                    anchors.fill: parent
                                    radius: parent.radius
                                    color: ColorUtils.applyAlpha(
                                        root.glassMode
                                            ? ColorUtils.mix(specialWorkspaceTile.baseColor, Appearance.colors.colLayer0, 0.40)
                                            : specialWorkspaceTile.baseColor,
                                        root.emptyWorkspaceWallpaperOverlayOpacity
                                    )
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton
                                    onClicked: {
                                        if (root.draggingTargetWorkspace === -1 && !root.draggingTargetSpecialWorkspace) {
                                            GlobalStates.overviewOpen = false;
                                            if (Hyprland.usingLua) {
                                                Hyprland.dispatch(`hl.dsp.workspace.toggle_special('${specialWorkspaceTile.specialName}')`);
                                            } else {
                                                Hyprland.dispatch(`togglespecialworkspace ${specialWorkspaceTile.specialName}`);
                                            }
                                        }
                                    }
                                }

                                DropArea {
                                    anchors.fill: parent
                                    onEntered: {
                                        root.draggingTargetWorkspace = -1;
                                        root.draggingTargetSpecialWorkspace = specialWorkspaceTile.specialName;
                                    }
                                    onExited: {
                                        if (root.draggingTargetSpecialWorkspace === specialWorkspaceTile.specialName)
                                            root.draggingTargetSpecialWorkspace = "";
                                    }
                                }

                                Item {
                                    id: specialWorkspaceContent
                                    x: specialWorkspaceTile.spread ? 0 : specialWorkspaceTile.contentOffsetX
                                    y: specialWorkspaceTile.spread ? 0 : specialWorkspaceTile.contentOffsetY
                                    width: specialWorkspaceTile.spread ? specialWorkspaceTile.width : specialWorkspaceTile.contentWidth
                                    height: specialWorkspaceTile.spread ? specialWorkspaceTile.height : specialWorkspaceTile.contentHeight
                                    clip: true

                                    Repeater {
                                        model: ScriptModel {
                                            values: {
                                                if (!specialWorkspaceTile.hasRenderableGeometry)
                                                    return [];
                                                return ToplevelManager.toplevels.values.filter((toplevel) => {
                                                    const address = `0x${toplevel.HyprlandToplevel.address}`;
                                                    const win = windowByAddress[address];
                                                    if ((win?.monitor ?? -1) !== (root.monitor?.id ?? -1))
                                                        return false;
                                                    return root.specialWorkspaceName(win) === specialWorkspaceTile.specialName;
                                                }).sort((a, b) => {
                                                    const addrA = `0x${a.HyprlandToplevel.address}`;
                                                    const addrB = `0x${b.HyprlandToplevel.address}`;
                                                    return addrA.localeCompare(addrB);
                                                });
                                            }
                                        }
                                        delegate: OverviewWindow {
                                            id: specialWindow
                                            required property var modelData
                                            required property int index
                                            property var address: `0x${modelData.HyprlandToplevel.address}`
                                            property int monitorId: windowData?.monitor
                                            property var monitor: HyprlandData.monitors.find(m => m.id === monitorId)
                                            property Item homeParent: specialWorkspaceContent
                                            windowData: windowByAddress[address]
                                            toplevel: modelData
                                            monitorData: monitor
                                            widgetMonitorData: root.monitorData
                                            scale: root.scale
                                            availableWorkspaceWidth: specialWorkspaceContent.width
                                            availableWorkspaceHeight: specialWorkspaceContent.height
                                            positionBaseX: Number.isFinite(specialWorkspaceTile.specialGeometry?.x) ? specialWorkspaceTile.specialGeometry.x : ((monitor?.x ?? 0) + (monitor?.reserved?.[0] ?? 0))
                                            positionBaseY: Number.isFinite(specialWorkspaceTile.specialGeometry?.y) ? specialWorkspaceTile.specialGeometry.y : ((monitor?.y ?? 0) + (monitor?.reserved?.[1] ?? 0))
                                            geometryScaleX: specialWorkspaceTile.fitScale / root.scale
                                            geometryScaleY: specialWorkspaceTile.fitScale / root.scale
                                            xOffset: 0
                                            yOffset: 0
                                            widgetMonitorId: root.monitor.id
                                            recaptureToken: root.previewRecaptureToken
                                            restrictToWorkspace: false
                                            animateSize: false
                                            layoutSlot: specialWorkspaceTile.layoutSlots?.[address] ?? null
                                            z: root.specialWindowZ(windowData)

                                            function moveToDragLayer() {
                                                const mapped = specialWindow.mapToItem(specialWindowDragLayer, 0, 0);
                                                specialWindow.suspendPositionAnimation = true;
                                                specialWindow.parent = specialWindowDragLayer;
                                                specialWindow.x = mapped.x;
                                                specialWindow.y = mapped.y;
                                                specialWindow.z = root.windowDraggingZ + 1;
                                                Qt.callLater(() => specialWindow.suspendPositionAnimation = false);
                                            }

                                            function returnToHomeParent() {
                                                specialWindow.suspendPositionAnimation = true;
                                                specialWindow.parent = homeParent;
                                                specialWindow.z = root.specialWindowZ(windowData);
                                                specialWindow.x = Qt.binding(() => specialWindow.initX);
                                                specialWindow.y = Qt.binding(() => specialWindow.initY);
                                                Qt.callLater(() => specialWindow.suspendPositionAnimation = false);
                                            }

                                            MouseArea {
                                                id: specialDragArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                onEntered: hovered = true
                                                onExited: hovered = false
                                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                                drag.target: parent
                                                onPressed: (mouse) => {
                                                    root.draggingFromWorkspace = -1
                                                    root.draggingTargetSpecialWorkspace = ""
                                                    specialWindow.pressed = true
                                                    specialWindow.dragInProgress = true
                                                    specialWindow.Drag.source = specialWindow
                                                    specialWindow.Drag.hotSpot.x = mouse.x
                                                    specialWindow.Drag.hotSpot.y = mouse.y
                                                    specialWindow.moveToDragLayer()
                                                    specialWindow.Drag.active = true
                                                }
                                                onReleased: {
                                                    const targetWorkspace = root.draggingTargetWorkspace
                                                    const targetSpecialWorkspace = root.draggingTargetSpecialWorkspace
                                                    specialWindow.pressed = false
                                                    specialWindow.Drag.active = false
                                                    specialWindow.dragInProgress = false
                                                    root.draggingFromWorkspace = -1
                                                    root.draggingTargetWorkspace = -1
                                                    root.draggingTargetSpecialWorkspace = ""
                                                    if (targetSpecialWorkspace === root.createSpecialWorkspaceTarget) {
                                                        const createdName = root.nextSpecialWorkspaceName()
                                                        //INFO: From special TO NEW special
                                                        if (Hyprland.usingLua) {
                                                            Hyprland.dispatch(`hl.dsp.window.move({workspace = 'special:${createdName}', follow = false, window = 'address:${specialWindow.windowData?.address}'})`);
                                                        } else {
                                                            Hyprland.dispatch(`movetoworkspacesilent special:${createdName}, address:${specialWindow.windowData?.address}`)
                                                        }
                                                        specialWindow.returnToHomeParent()
                                                    }
                                                    else if (targetSpecialWorkspace && targetSpecialWorkspace !== specialWorkspaceTile.specialName) {
                                                        // Idk
                                                        if (Hyprland.usingLua) {
                                                            Hyprland.dispatch(`hl.dsp.window.move({workspace = 'special:${targetSpecialWorkspace}', follow = false, window = 'address:${specialWindow.windowData?.address}'})`);
                                                        } else {
                                                            Hyprland.dispatch(`movetoworkspacesilent special:${targetSpecialWorkspace}, address:${specialWindow.windowData?.address}`)
                                                        }
                                                        specialWindow.returnToHomeParent()
                                                    }
                                                    else if (targetWorkspace !== -1) {
                                                        //INFO: From Special TO Normal workspace
                                                        if (Hyprland.usingLua) {
                                                            Hyprland.dispatch(`hl.dsp.window.move({workspace = '${targetWorkspace}', follow = false, window = 'address:${specialWindow.windowData?.address}'})`);
                                                        } else {
                                                            Hyprland.dispatch(`movetoworkspacesilent ${targetWorkspace}, address:${specialWindow.windowData?.address}`)
                                                        }
                                                        specialWindow.returnToHomeParent()
                                                    }
                                                    else {
                                                        specialWindow.returnToHomeParent()
                                                    }
                                                }
                                                onClicked: (event) => {
                                                    if (!windowData)
                                                        return;
                                                    if (event.button === Qt.LeftButton) {
                                                        GlobalStates.overviewOpen = false;
                                                        if (Hyprland.usingLua) {
                                                            Hyprland.dispatch(`hl.dsp.focus({ window = 'address:${windowData.address}' })`);
                                                        } else {
                                                            Hyprland.dispatch(`focuswindow address:${windowData.address}`);
                                                        }
                                                        event.accepted = true;
                                                    } else if (event.button === Qt.MiddleButton) {
                                                        if (Hyprland.usingLua) {
                                                            Hyprland.dispatch(`hl.dsp.window.close('address:${windowData.address}')`);
                                                        } else {
                                                            Hyprland.dispatch(`closewindow address:${windowData.address}`);
                                                        }
                                                        event.accepted = true;
                                                    }
                                                }

                                                StyledToolTip {
                                                    extraVisibleCondition: false
                                                    alternativeVisibleCondition: specialDragArea.containsMouse && !specialWindow.Drag.active
                                                    text: `${windowData?.title ?? "Unknown"}\n[${windowData?.class ?? "unknown"}] ${windowData?.xwayland ? "[XWayland] " : ""}`
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        Rectangle {
                            id: createSpecialWorkspaceTile
                            property bool showWallpaper: root.hasSpecialEmptyWorkspaceWallpaper
                            implicitWidth: root.specialWorkspaceTileWidth
                            implicitHeight: root.specialWorkspaceTileHeight
                            radius: Appearance.rounding.screenRounding * root.scale
                            color: showWallpaper ? "transparent" : ColorUtils.applyAlpha(
                                root.glassMode
                                    ? ColorUtils.mix(Appearance.colors.colSecondaryContainer, Appearance.colors.colLayer1, 0.58)
                                    : ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colLayer1, 0.55),
                                root.draggingTargetSpecialWorkspace === root.createSpecialWorkspaceTarget ? 0.90 : root.effectiveWorkspaceOpacity
                            )
                            border.width: 1
                            border.color: root.draggingTargetSpecialWorkspace === root.createSpecialWorkspaceTarget
                                ? ColorUtils.applyAlpha(root.activeBorderColor, 0.96)
                                : ColorUtils.applyAlpha(Appearance.colors.colSecondary, 0.46)

                            Image {
                                visible: createSpecialWorkspaceTile.showWallpaper
                                anchors.fill: parent
                                source: root.wallpaperSource(root.specialEmptyWorkspaceWallpaperPath)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                                smooth: true
                                mipmap: true
                            }

                            Rectangle {
                                visible: createSpecialWorkspaceTile.showWallpaper
                                anchors.fill: parent
                                radius: parent.radius
                                color: ColorUtils.applyAlpha(
                                    root.glassMode
                                        ? ColorUtils.mix(Appearance.colors.colSecondaryContainer, Appearance.colors.colLayer0, 0.40)
                                        : ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colLayer1, 0.55),
                                    root.draggingTargetSpecialWorkspace === root.createSpecialWorkspaceTarget
                                        ? Math.min(0.28, root.emptyWorkspaceWallpaperOverlayOpacity + 0.08)
                                        : root.emptyWorkspaceWallpaperOverlayOpacity
                                )
                            }

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: Math.max(parent.radius - 1, 0)
                                color: "transparent"
                                border.width: 1
                                border.color: ColorUtils.applyAlpha("#FFFFFF", root.glassMode ? 0.12 : 0.08)
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: 0

                                StyledText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    visible: !createSpecialWorkspaceTile.showWallpaper
                                    text: root.draggingTargetSpecialWorkspace === root.createSpecialWorkspaceTarget ? "Release" : "+"
                                    font.family: Appearance.font.family.expressive
                                    font.pixelSize: root.draggingTargetSpecialWorkspace === root.createSpecialWorkspaceTarget
                                        ? Appearance.font.pixelSize.larger * root.scale
                                        : Appearance.font.pixelSize.huge * 1.25 * root.scale
                                    font.weight: Font.DemiBold
                                    color: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.92)
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                onClicked: {
                                    const createdName = root.nextSpecialWorkspaceName();
                                    GlobalStates.overviewOpen = false;
                                    if (Hyprland.usingLua) {
                                        Hyprland.dispatch(`hl.dsp.workspace.toggle_special('${createdName}')`);
                                    } else {
                                        Hyprland.dispatch(`togglespecialworkspace ${createdName}`);
                                    }
                                }
                            }

                            DropArea {
                                anchors.fill: parent
                                onEntered: {
                                    root.draggingTargetWorkspace = -1;
                                    root.draggingTargetSpecialWorkspace = root.createSpecialWorkspaceTarget;
                                }
                                onExited: {
                                    if (root.draggingTargetSpecialWorkspace === root.createSpecialWorkspaceTarget)
                                        root.draggingTargetSpecialWorkspace = "";
                                }
                            }
                        }
                    }
                }
            }
        }

        Item { // Windows & focused workspace indicator
            id: windowSpace
            anchors.centerIn: parent
            implicitWidth: contentLayout.implicitWidth
            implicitHeight: contentLayout.implicitHeight

            QtObject {
                id: workspaceWheel
                property real accumulated: 0
                property bool locked: false

                function handle(event, horizontal) {
                    const dx = event.angleDelta.x;
                    const dy = event.angleDelta.y;
                    // Each axis has its own handler; only the dominant axis of an event acts.
                    if (horizontal !== (Math.abs(dx) > Math.abs(dy)))
                        return;
                    const delta = horizontal ? dx : dy;
                    if (!delta)
                        return;
                    event.accepted = true;
                    if (root.scrollSwitch !== "gesture") {
                        root.stepWorkspace(delta > 0 ? -1 : 1);
                        return;
                    }
                    // One step per gesture: keep the lock while events (incl. touchpad inertia) keep arriving.
                    wheelIdleTimer.restart();
                    if (locked)
                        return;
                    if (Math.sign(delta) !== Math.sign(accumulated))
                        accumulated = 0;
                    accumulated += delta;
                    if (Math.abs(accumulated) < 120)
                        return;
                    root.stepWorkspace(accumulated > 0 ? -1 : 1);
                    accumulated = 0;
                    locked = true;
                }
            }

            WheelHandler {
                target: null
                enabled: root.scrollSwitch !== "off"
                orientation: Qt.Vertical
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => workspaceWheel.handle(event, false)
            }

            WheelHandler {
                target: null
                enabled: root.scrollSwitch !== "off"
                orientation: Qt.Horizontal
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => workspaceWheel.handle(event, true)
            }

            Timer {
                id: wheelIdleTimer
                interval: Math.max(50, Config.options.overview.scrollCooldownMs)
                onTriggered: {
                    workspaceWheel.locked = false;
                    workspaceWheel.accumulated = 0;
                }
            }

            Repeater { // Window repeater
                model: ScriptModel {
                    values: {
                        return ToplevelManager.toplevels.values.filter((toplevel) => {
                            const address = `0x${toplevel.HyprlandToplevel.address}`
                            var win = windowByAddress[address]
                            if (root.isSpecialWorkspace(win))
                                return false;
                            const minWorkspace = root.workspaceGroup * root.workspacesShown + 1 + workspaceOffset;
                            const maxWorkspace = (root.workspaceGroup + 1) * root.workspacesShown + workspaceOffset;
                            const inWorkspaceGroup = (minWorkspace <= win?.workspace?.id && win?.workspace?.id <= maxWorkspace)
                            return inWorkspaceGroup;
                        }).sort((a, b) => {
                            // Proper stacking order based on Hyprland's window properties
                            const addrA = `0x${a.HyprlandToplevel.address}`
                            const addrB = `0x${b.HyprlandToplevel.address}`
                            const winA = windowByAddress[addrA]
                            const winB = windowByAddress[addrB]

                            // 1. Pinned windows are always on top
                            if (winA?.pinned !== winB?.pinned) {
                                return winA?.pinned ? 1 : -1
                            }

                            // 2. Floating windows above tiled windows
                            if (winA?.floating !== winB?.floating) {
                                return winA?.floating ? 1 : -1
                            }

                            // 3. Within same category, sort by focus history
                            // Lower focusHistoryID = more recently focused = higher in stack
                            return (winB?.focusHistoryID ?? 0) - (winA?.focusHistoryID ?? 0)
                        })
                    }
                }
                delegate: OverviewWindow {
                    id: window
                    required property var modelData
                    required property int index
                    property int monitorId: windowData?.monitor
                    property var monitor: HyprlandData.monitors.find(m => m.id === monitorId)
                    property var address: `0x${modelData.HyprlandToplevel.address}`
                    windowData: windowByAddress[address]
                    toplevel: modelData
                    monitorData: monitor
                    widgetMonitorData: root.monitorData
                    property var cell: root.workspaceCell(windowData?.workspace?.id)
                    scale: cell.scale
                    availableWorkspaceWidth: cell.width
                    availableWorkspaceHeight: cell.height
                    widgetMonitorId: root.monitor.id
                    recaptureToken: root.previewRecaptureToken
                    layoutSlot: root.workspaceLayoutSlots[address] ?? null

                    property bool atInitPosition: (initX == x && initY == y)

                    xOffset: cell.x
                    yOffset: cell.y

                    function snapToInitPosition() {
                        window.x = Qt.binding(() => window.initX)
                        window.y = Qt.binding(() => window.initY)
                    }

                    Timer {
                        id: updateWindowPosition
                        interval: Config.options.hacks.arbitraryRaceConditionDelay
                        repeat: false
                        running: false
                        onTriggered: window.snapToInitPosition()
                    }

                    z: atInitPosition ? (root.windowZ + index) : root.windowDraggingZ
                    Drag.hotSpot.x: targetWindowWidth / 2
                    Drag.hotSpot.y: targetWindowHeight / 2
                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: hovered = true
                        onExited: hovered = false
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        drag.target: parent
                        onPressed: (mouse) => {
                            root.draggingFromWorkspace = windowData?.workspace.id
                            root.draggingTargetSpecialWorkspace = ""
                            window.pressed = true
                            window.Drag.active = true
                            window.Drag.source = window
                            window.Drag.hotSpot.x = mouse.x
                            window.Drag.hotSpot.y = mouse.y
                        }
                        onReleased: {
                            const targetWorkspace = root.draggingTargetWorkspace
                            const targetSpecialWorkspace = root.draggingTargetSpecialWorkspace
                            window.pressed = false
                            window.Drag.active = false
                            root.draggingFromWorkspace = -1
                            root.draggingTargetWorkspace = -1
                            root.draggingTargetSpecialWorkspace = ""
                            if (targetSpecialWorkspace === root.createSpecialWorkspaceTarget) {
                                const createdName = root.nextSpecialWorkspaceName()
                                //INFO: From normal TO special
                                if (Hyprland.usingLua) {
                                    Hyprland.dispatch(`hl.dsp.window.move({workspace = 'special:${createdName}', follow = false, window = 'address:${window.windowData?.address}'})`);
                                } else {
                                    Hyprland.dispatch(`movetoworkspacesilent special:${createdName}, address:${window.windowData?.address}`)
                                }
                                updateWindowPosition.restart()
                            }
                            else if (targetSpecialWorkspace && targetSpecialWorkspace !== root.specialWorkspaceName(windowData)) {
                                // Idk
                                if (Hyprland.usingLua) {
                                    Hyprland.dispatch(`hl.dsp.window.move({workspace = 'special:${targetSpecialWorkspace}', follow = false, window = 'address:${window.windowData?.address}'})`);
                                } else {
                                    Hyprland.dispatch(`movetoworkspacesilent special:${targetSpecialWorkspace}, address:${window.windowData?.address}`)
                                }
                                updateWindowPosition.restart()
                            }
                            else if (targetWorkspace !== -1 && targetWorkspace !== windowData?.workspace.id) {
                                //INFO: From normal TO normal
                                if (Hyprland.usingLua) {
                                    Hyprland.dispatch(`hl.dsp.window.move({workspace = '${targetWorkspace}', follow = false, window = 'address:${window.windowData?.address}'})`);
                                } else {
                                    Hyprland.dispatch(`movetoworkspacesilent ${targetWorkspace}, address:${window.windowData?.address}`)
                                }
                                updateWindowPosition.restart()
                            }
                            else {
                                window.snapToInitPosition()
                            }
                        }
                        onClicked: (event) => {
                            if (!windowData) return;

                            if (event.button === Qt.LeftButton) {
                                GlobalStates.overviewOpen = false
                                if (Hyprland.usingLua) {
                                    Hyprland.dispatch(`hl.dsp.focus({ window = 'address:${windowData.address}' })`);
                                } else {
                                    Hyprland.dispatch(`focuswindow address:${windowData.address}`)
                                }
                                event.accepted = true
                            } else if (event.button === Qt.MiddleButton) {
                                if (Hyprland.usingLua) {
                                    Hyprland.dispatch(`hl.dsp.window.close('address:${windowData.address}')`);
                                } else {
                                    Hyprland.dispatch(`closewindow address:${windowData.address}`)
                                }
                                event.accepted = true
                            }
                        }

                        StyledToolTip {
                            extraVisibleCondition: false
                            alternativeVisibleCondition: dragArea.containsMouse && !window.Drag.active
                            text: `${windowData?.title ?? "Unknown"}\n[${windowData?.class ?? "unknown"}] ${windowData?.xwayland ? "[XWayland] " : ""}`
                        }
                    }
                }
            }

            Rectangle { // Focused workspace indicator
                id: focusedWorkspaceIndicator
                property var cell: root.workspaceCell(root.effectiveActiveWorkspaceId)
                x: cell.x
                y: cell.y
                z: root.windowDraggingZ - 1
                width: cell.width
                height: cell.height
                color: "transparent"
                radius: Appearance.rounding.screenRounding * cell.scale
                border.width: 2
                border.color: root.activeBorderColor
                Behavior on x {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on y {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }

        Item {
            id: specialWindowDragLayer
            anchors.fill: parent
            z: root.windowDraggingZ + 1
        }
    }
}
