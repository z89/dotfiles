pragma ComponentBehavior: Bound

import QtQml
import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

FocusScope {
    id: content

    property real scrollStep: 60
    property var activeFlickable: mainFlickable
    property bool showFloatingToggle: true
    property bool floating: false
    property alias searchField: searchField

    signal closeRequested
    signal floatingToggleRequested

    function categoryIcon(category) {
        const name = String(category || "").toLowerCase();
        if (name.includes("window"))
            return "web_asset";
        if (name.includes("workspace"))
            return "space_dashboard";
        if (name.includes("media") || name.includes("audio") || name.includes("music"))
            return "play_circle";
        if (name.includes("screen") || name.includes("capture"))
            return "screenshot_monitor";
        if (name.includes("app") || name.includes("launch"))
            return "apps";
        if (name.includes("system") || name.includes("session"))
            return "settings";
        return "keyboard";
    }

    function prettyKey(key) {
        const value = String(key || "").trim();
        const aliases = {
            "super": "Super",
            "ctrl": "Ctrl",
            "control": "Ctrl",
            "alt": "Alt",
            "shift": "Shift",
            "return": "Enter",
            "escape": "Esc",
            "space": "Space",
            "period": ".",
            "comma": ",",
            "slash": "/",
            "left": "←",
            "right": "→",
            "up": "↑",
            "down": "↓"
        };
        return aliases[value.toLowerCase()] || value;
    }

    function scrollDown() {
        if (!activeFlickable)
            return;
        let newY = activeFlickable.contentY + scrollStep;
        newY = Math.min(newY, activeFlickable.contentHeight - activeFlickable.height);
        activeFlickable.contentY = newY;
    }

    function scrollUp() {
        if (!activeFlickable)
            return;
        let newY = activeFlickable.contentY - scrollStep;
        newY = Math.max(0, newY);
        activeFlickable.contentY = newY;
    }

    Keys.onPressed: event => {
        switch (event.key) {
        case Qt.Key_J:
            if (event.modifiers & Qt.ControlModifier) {
                scrollDown();
                event.accepted = true;
            }
            return;
        case Qt.Key_K:
            if (event.modifiers & Qt.ControlModifier) {
                scrollUp();
                event.accepted = true;
            }
            return;
        case Qt.Key_Down:
            scrollDown();
            event.accepted = true;
            return;
        case Qt.Key_Up:
            scrollUp();
            event.accepted = true;
            return;
        }
    }

    Column {
        id: pageLayout

        anchors.fill: parent
        anchors.margins: Theme.spacingL
        spacing: Theme.spacingL

        Item {
            id: header

            width: parent.width
            height: 48

            Rectangle {
                id: headerIcon

                width: 44
                height: 44
                radius: Theme.cornerRadius
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.withAlpha(Theme.primary, 0.14)
                border.color: Theme.withAlpha(Theme.primary, 0.22)
                border.width: 1

                DankIcon {
                    anchors.centerIn: parent
                    name: "keyboard"
                    size: 23
                    color: Theme.primary
                }
            }

            Column {
                anchors.left: headerIcon.right
                anchors.leftMargin: Theme.spacingM
                anchors.right: rightTools.left
                anchors.rightMargin: Theme.spacingL
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXXS

                StyledText {
                    width: parent.width
                    text: I18n.tr("Keyboard Shortcuts")
                    font.pixelSize: Theme.fontSizeXLarge
                    font.weight: Font.DemiBold
                    color: Theme.surfaceText
                    elide: Text.ElideRight
                }

                StyledText {
                    width: parent.width
                    text: searchField.text.trim().length > 0 ? I18n.tr("%1 matching shortcuts").arg(mainFlickable.visibleBindCount) : I18n.tr("%1 shortcuts available").arg(mainFlickable.visibleBindCount)
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    elide: Text.ElideRight
                }
            }

            Row {
                id: rightTools

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingS

                DankTextField {
                    id: searchField

                    width: Math.min(380, Math.max(240, header.width * 0.36))
                    height: 44
                    leftIconName: "search"
                    leftIconSize: 20
                    placeholderText: I18n.tr("Search shortcuts")
                    hidePlaceholderOnFocus: false
                    showClearButton: true
                    keyForwardTargets: [content]
                    onTextEdited: searchDebounce.restart()
                    Keys.onEscapePressed: event => {
                        content.closeRequested();
                        event.accepted = true;
                    }
                }

                DankActionButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: content.showFloatingToggle
                    iconName: content.floating ? "close_fullscreen" : "open_in_new"
                    tooltipText: content.floating ? I18n.tr("Dock window") : I18n.tr("Open as window")
                    onClicked: content.floatingToggleRequested()
                }
            }
        }

        Timer {
            id: searchDebounce

            interval: 50
            repeat: false
            onTriggered: mainFlickable.categories = mainFlickable.generateCategories(searchField.text)
        }

        Item {
            id: resultsArea

            width: parent.width
            height: Math.max(0, parent.height - header.height - parent.spacing)

            DankFlickable {
                id: mainFlickable

                anchors.fill: parent
                contentWidth: width
                contentHeight: rowLayout.implicitHeight + Theme.spacingS
                clip: true

                property var rawBinds: KeybindsService.cheatsheet.binds || {}
                property var categories: generateCategories("")
                property var categoryKeys: Object.keys(categories)
                readonly property real scrollGutter: Theme.spacingL + Theme.spacingXXS
                readonly property int visibleBindCount: {
                    let count = 0;
                    for (const category of categoryKeys) {
                        const data = categories[category];
                        for (const subcategory of data?.subcatKeys || [])
                            count += data.subcats[subcategory]?.length || 0;
                    }
                    return count;
                }

                function generateCategories(query) {
                    const lowerQuery = query ? query.toLowerCase().trim() : "";
                    const lowerQueryWords = lowerQuery.split(/\s+/);
                    const processed = {};

                    for (const cat in rawBinds) {
                        const binds = rawBinds[cat];
                        const catLower = cat.toLowerCase();
                        const subcats = {};
                        let hasSubcats = false;
                        for (let i = 0; i < binds.length; i++) {
                            const bind = binds[i];
                            const keyLower = (bind.key || "").toLowerCase();
                            const descLower = (bind.desc || "").toLowerCase();
                            const actionLower = (bind.action || "").toLowerCase();

                            if (bind.hideOnOverlay)
                                continue;
                            let shouldContinue = false;
                            for (let j = 0; j < lowerQueryWords.length; j++) {
                                const word = lowerQueryWords[j];
                                if (!(word.length === 0 || keyLower.includes(word) || descLower.includes(word) || catLower.includes(word) || actionLower.includes(word))) {
                                    shouldContinue = true;
                                    break;
                                }
                            }
                            if (shouldContinue)
                                continue;

                            if (bind.subcat) {
                                hasSubcats = true;
                                if (!subcats[bind.subcat])
                                    subcats[bind.subcat] = [];
                                subcats[bind.subcat].push(bind);
                            } else {
                                if (!subcats["_root"])
                                    subcats["_root"] = [];
                                subcats["_root"].push(bind);
                            }
                        }

                        if (Object.keys(subcats).length === 0)
                            continue;

                        processed[cat] = {
                            "hasSubcats": hasSubcats,
                            "subcats": subcats,
                            "subcatKeys": Object.keys(subcats)
                        };
                    }

                    return processed;
                }

                function estimateCategoryHeight(catName) {
                    const catData = categories[catName];
                    if (!catData)
                        return 0;
                    let bindCount = 0;
                    let subcategoryCount = 0;
                    for (const key of catData.subcatKeys) {
                        bindCount += catData.subcats[key]?.length || 0;
                        if (key !== "_root")
                            subcategoryCount += 1;
                    }
                    return 76 + bindCount * 40 + subcategoryCount * 24;
                }

                function distributeCategories(cols) {
                    const columns = [];
                    const heights = [];
                    for (let i = 0; i < cols; i++) {
                        columns.push([]);
                        heights.push(0);
                    }
                    const sorted = [...categoryKeys].sort((a, b) => estimateCategoryHeight(b) - estimateCategoryHeight(a));
                    for (const cat of sorted) {
                        let minIdx = 0;
                        for (let i = 1; i < cols; i++) {
                            if (heights[i] < heights[minIdx])
                                minIdx = i;
                        }
                        columns[minIdx].push(cat);
                        heights[minIdx] += estimateCategoryHeight(cat) + Theme.spacingM;
                    }
                    return columns;
                }

                Row {
                    id: rowLayout

                    width: Math.max(0, mainFlickable.width - mainFlickable.scrollGutter)
                    spacing: Theme.spacingM

                    property int numColumns: Math.max(1, Math.min(3, Math.floor(width / 340)))
                    property var columnCategories: mainFlickable.distributeCategories(numColumns)

                    Repeater {
                        model: rowLayout.numColumns

                        Column {
                            id: masonryColumn

                            required property int index

                            width: (rowLayout.width - rowLayout.spacing * (rowLayout.numColumns - 1)) / rowLayout.numColumns
                            spacing: Theme.spacingM

                            Repeater {
                                model: rowLayout.columnCategories[masonryColumn.index] || []

                                Rectangle {
                                    id: categoryCard

                                    required property string modelData

                                    property string catName: modelData
                                    property var catData: mainFlickable.categories[catName]
                                    readonly property int bindCount: {
                                        let count = 0;
                                        for (const key of catData?.subcatKeys || [])
                                            count += catData.subcats[key]?.length || 0;
                                        return count;
                                    }

                                    width: masonryColumn.width
                                    height: cardContent.implicitHeight + Theme.spacingM * 2
                                    radius: Theme.cornerRadius
                                    color: Theme.popupFieldColor
                                    border.color: Theme.popupFieldBorderColor
                                    border.width: 1

                                    Column {
                                        id: cardContent

                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: Theme.spacingM
                                        spacing: Theme.spacingS

                                        Item {
                                            width: parent.width
                                            height: 34

                                            Rectangle {
                                                id: categoryIconWell

                                                width: 32
                                                height: 32
                                                radius: 10
                                                anchors.left: parent.left
                                                anchors.verticalCenter: parent.verticalCenter
                                                color: Theme.withAlpha(Theme.primary, 0.12)

                                                DankIcon {
                                                    anchors.centerIn: parent
                                                    name: content.categoryIcon(categoryCard.catName)
                                                    size: 18
                                                    color: Theme.primary
                                                }
                                            }

                                            StyledText {
                                                anchors.left: categoryIconWell.right
                                                anchors.leftMargin: Theme.spacingS
                                                anchors.right: categoryCount.left
                                                anchors.rightMargin: Theme.spacingS
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: categoryCard.catName
                                                font.pixelSize: Theme.fontSizeMedium
                                                font.weight: Font.DemiBold
                                                color: Theme.surfaceText
                                                elide: Text.ElideRight
                                            }

                                            Rectangle {
                                                id: categoryCount

                                                width: countText.implicitWidth + Theme.spacingS * 2
                                                height: 24
                                                radius: height / 2
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                color: Theme.withAlpha(Theme.surfaceVariant, 0.18)

                                                StyledText {
                                                    id: countText

                                                    anchors.centerIn: parent
                                                    text: categoryCard.bindCount
                                                    font.pixelSize: Theme.fontSizeSmall - 1
                                                    font.weight: Font.Medium
                                                    color: Theme.surfaceVariantText
                                                }
                                            }
                                        }

                                        Rectangle {
                                            width: parent.width
                                            height: 1
                                            color: Theme.withAlpha(Theme.outline, 0.16)
                                        }

                                        Column {
                                            width: parent.width
                                            spacing: Theme.spacingS

                                            Repeater {
                                                model: categoryCard.catData?.subcatKeys || []

                                                Column {
                                                    id: subcategoryColumn

                                                    required property string modelData

                                                    property string subcatName: modelData
                                                    property var subcatBinds: categoryCard.catData?.subcats?.[subcatName] || []

                                                    width: parent.width
                                                    spacing: Theme.spacingXXS

                                                    StyledText {
                                                        visible: subcategoryColumn.subcatName !== "_root"
                                                        width: parent.width
                                                        leftPadding: Theme.spacingS
                                                        bottomPadding: Theme.spacingXXS
                                                        text: subcategoryColumn.subcatName
                                                        font.pixelSize: Theme.fontSizeSmall - 1
                                                        font.weight: Font.DemiBold
                                                        font.capitalization: Font.AllUppercase
                                                        font.letterSpacing: 0.7
                                                        color: Theme.surfaceVariantText
                                                        opacity: 0.72
                                                        elide: Text.ElideRight
                                                    }

                                                    Column {
                                                        width: parent.width
                                                        spacing: Theme.spacingXXS

                                                        Repeater {
                                                            model: subcategoryColumn.subcatBinds

                                                            Item {
                                                                id: bindRow

                                                                required property var modelData

                                                                property var bindData: modelData
                                                                property var keyParts: String(bindData.key || "").split("+").map(part => part.trim()).filter(part => part.length > 0)

                                                                width: parent.width
                                                                height: 38

                                                                Rectangle {
                                                                    anchors.fill: parent
                                                                    radius: Math.max(6, Theme.cornerRadius - 4)
                                                                    color: bindMouse.containsMouse ? Theme.surfaceHover : Theme.withAlpha(Theme.surfaceHover, 0)

                                                                    Behavior on color {
                                                                        ColorAnimation {
                                                                            duration: 90
                                                                            easing.type: Theme.standardEasing
                                                                        }
                                                                    }
                                                                }

                                                                MouseArea {
                                                                    id: bindMouse

                                                                    anchors.fill: parent
                                                                    acceptedButtons: Qt.NoButton
                                                                    hoverEnabled: true
                                                                }

                                                                StyledText {
                                                                    anchors.left: parent.left
                                                                    anchors.leftMargin: Theme.spacingS
                                                                    anchors.right: keyCaps.left
                                                                    anchors.rightMargin: Theme.spacingM
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    text: bindRow.bindData.desc || bindRow.bindData.action || ""
                                                                    font.pixelSize: Theme.fontSizeSmall
                                                                    color: Theme.surfaceText
                                                                    elide: Text.ElideRight
                                                                    wrapMode: Text.NoWrap
                                                                }

                                                                Row {
                                                                    id: keyCaps

                                                                    anchors.right: parent.right
                                                                    anchors.rightMargin: Theme.spacingS
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    spacing: Theme.spacingXXS

                                                                    Repeater {
                                                                        model: bindRow.keyParts

                                                                        Rectangle {
                                                                            id: keyCap

                                                                            required property string modelData

                                                                            width: keyCapText.implicitWidth + 12
                                                                            height: 23
                                                                            radius: 6
                                                                            color: Theme.withAlpha(Theme.primary, 0.10)
                                                                            border.color: Theme.withAlpha(Theme.primary, 0.20)
                                                                            border.width: 1

                                                                            StyledText {
                                                                                id: keyCapText

                                                                                anchors.centerIn: parent
                                                                                text: content.prettyKey(keyCap.modelData)
                                                                                font.pixelSize: Theme.fontSizeSmall - 1
                                                                                font.weight: Font.Medium
                                                                                color: Theme.primary
                                                                            }
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: mainFlickable.visibleBindCount === 0

                Column {
                    anchors.centerIn: parent
                    width: Math.min(360, parent.width - Theme.spacingXL * 2)
                    spacing: Theme.spacingS

                    Rectangle {
                        width: 52
                        height: 52
                        radius: Theme.cornerRadius
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: Theme.withAlpha(Theme.primary, 0.12)

                        DankIcon {
                            anchors.centerIn: parent
                            name: "search_off"
                            size: 26
                            color: Theme.primary
                        }
                    }

                    StyledText {
                        width: parent.width
                        topPadding: Theme.spacingS
                        text: I18n.tr("No shortcuts found")
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.DemiBold
                        color: Theme.surfaceText
                        horizontalAlignment: Text.AlignHCenter
                    }

                    StyledText {
                        width: parent.width
                        text: I18n.tr("Try a key, action, or category")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }
}
