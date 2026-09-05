        // dms-shell-patch: compact banner card. Replaces the stock card body from the
        // critical-accent rectangle up to (not including) the cardHoverArea MouseArea.
        // Critical urgency gets a short inset pill on the leading edge, drawn inside the
        // card so it reads against any wallpaper; everything else stays flat.
        Rectangle {
            x: content.cardInset + 8
            y: content.cardInset + 10
            width: 3
            height: Math.max(0, content.height - content.cardInset * 2 - 20)
            radius: width / 2
            visible: win.isCritical
            color: Theme.error
            scale: content.chromeScale
            transformOrigin: Item.Center
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: content.cardInset
            radius: win.connectedFrameMode ? Theme.connectedSurfaceRadius : Theme.cornerRadius
            color: "transparent"
            border.color: win.connectedFrameMode ? Theme.withAlpha(BlurService.borderColor, 0) : BlurService.borderColor
            border.width: win.connectedFrameMode ? 0 : BlurService.borderWidth
            z: 100
            scale: content.chromeScale
            transformOrigin: Item.Center
        }

        Item {
            id: backgroundContainer
            anchors.fill: parent
            anchors.margins: content.cardInset
            clip: true

            readonly property bool privacyCollapsed: SettingsData.notificationPopupPrivacyMode && !win.descriptionExpanded
            readonly property bool critical: win.notificationData && win.notificationData.urgency === NotificationUrgency.Critical
            readonly property real textColumnWidth: Math.max(0, width - win.cardPaddingH * 2 - win.popupIconSize - win.iconTextGap)
            readonly property real collapsedBlockHeight: privacyCollapsed ? win.privacyTextBlockHeight : win.textBlockHeight

            HoverHandler {
                id: cardHoverHandler
            }

            Connections {
                target: cardHoverHandler
                function onHoveredChanged() {
                    if (!notificationData || win.exiting || win._isDestroying)
                        return;
                    if (cardHoverHandler.hovered) {
                        if (notificationData.timer)
                            notificationData.timer.stop();
                    } else if (!win.contextMenuActive && notificationData.popup && notificationData.timer) {
                        notificationData.timer.restart();
                    }
                }
            }

            // Timeout: a 2px hairline along the bottom edge drains right-to-left as the
            // dismiss timer runs; inset by the corner radius, frozen while hovered.
            Rectangle {
                id: timeoutBar

                readonly property bool active: SettingsData.notificationShowTimeoutBar && notificationData && notificationData.timer && notificationData.timer.interval > 0
                property real progress: 1
                readonly property real surfaceRadius: win.connectedFrameMode ? Theme.connectedSurfaceRadius : Theme.cornerRadius

                visible: active && progress > 0
                anchors.left: parent.left
                anchors.leftMargin: surfaceRadius
                anchors.bottom: parent.bottom
                width: Math.max(0, parent.width - surfaceRadius * 2) * progress
                height: Math.max(1, Theme.snap(2, win.dpr))
                radius: height / 2
                z: 50
                opacity: 0.55
                color: backgroundContainer.critical ? Theme.error : Theme.primary

                NumberAnimation {
                    id: progressAnim
                    target: timeoutBar
                    property: "progress"
                    from: 1
                    to: 0
                    duration: (notificationData && notificationData.timer && notificationData.timer.interval > 0) ? notificationData.timer.interval : 5000
                    running: timeoutBar.active && notificationData && notificationData.timer && notificationData.timer.running && !win.exiting
                    easing.type: Easing.Linear
                }

                Connections {
                    target: timeoutBar.active ? notificationData.timer : null
                    function onRunningChanged() {
                        if (notificationData && notificationData.timer && notificationData.timer.running && !win.exiting) {
                            timeoutBar.progress = 1;
                            progressAnim.restart();
                        }
                    }
                }
            }

            LayoutMirroring.enabled: I18n.isRtl
            LayoutMirroring.childrenInherit: true

            // Hidden measuring copies of the body: the card height is derived from the
            // text that is actually rendered, so a one-line body gives a one-line card.
            StyledText {
                id: expandedBodyMeasure

                visible: false
                width: backgroundContainer.textColumnWidth
                text: notificationData ? (notificationData.htmlBody || "") : ""
                textFormat: Text.StyledText
                font.pixelSize: win.bodyFontSize
                lineHeight: win.bodyLineRatio
                lineHeightMode: Text.ProportionalHeight
                elide: Text.ElideNone
                horizontalAlignment: Text.AlignLeft
                maximumLineCount: -1
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            }

            StyledText {
                id: collapsedBodyMeasure

                visible: false
                width: backgroundContainer.textColumnWidth
                text: notificationData ? (notificationData.htmlBody || "") : ""
                textFormat: Text.StyledText
                font.pixelSize: win.bodyFontSize
                lineHeight: win.bodyLineRatio
                lineHeightMode: Text.ProportionalHeight
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignLeft
                maximumLineCount: win.collapsedBodyLines
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            }

            // Single-line metrics for the title and body fonts, so the card height comes
            // from the real font, not a guessed multiplier.
            StyledText {
                id: titleMeasure
                visible: false
                text: "Ag"
                font.pixelSize: win.titleFontSize
                font.weight: Font.DemiBold
            }

            StyledText {
                id: bodyLineMeasure
                visible: false
                text: "Ag"
                font.pixelSize: win.bodyFontSize
                lineHeight: win.bodyLineRatio
                lineHeightMode: Text.ProportionalHeight
            }

            Item {
                id: notificationContent

                readonly property real extraHeight: win.descriptionExpanded ? Math.max(0, win.expandedBodyHeight - win.collapsedBodyHeight) : 0

                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                // Text-led cards keep the optical top/bottom split; icon-led cards (title
                // only) centre the icon between the two paddings instead.
                anchors.topMargin: win.cardPadding + (backgroundContainer.collapsedBlockHeight < win.popupIconSize ? Math.round((win.cardPaddingBottom - win.cardPadding) / 2) : 0)
                anchors.leftMargin: win.cardPaddingH
                anchors.rightMargin: win.cardPaddingH
                height: Math.max(win.popupIconSize, backgroundContainer.collapsedBlockHeight) + extraHeight

                DankRoundedImage {
                    id: iconContainer
                    cacheImages: false
                    cornerRadius: Math.round(win.popupIconSize * 0.28)

                    readonly property bool hasDisplayImage: notificationData?.hasDisplayImage ?? false
                    readonly property bool needsImagePersist: {
                        if (!hasDisplayImage || notificationData.persistedImagePath)
                            return false;
                        const image = notificationData.image || "";
                        return image.startsWith("image://qsimage/") || NotificationService.notificationIconFromImage(image).startsWith("/");
                    }

                    width: win.popupIconSize
                    height: win.popupIconSize
                    anchors.left: parent.left
                    anchors.top: parent.top
                    // Centred on the collapsed text block; stays put when the body expands.
                    anchors.topMargin: Math.max(0, Math.round((backgroundContainer.collapsedBlockHeight - win.popupIconSize) / 2))

                    imageSource: notificationData?.displayImage ?? ""
                    hasImage: hasDisplayImage
                    fallbackIcon: notificationData?.fallbackIconName ?? ""
                    fallbackText: {
                        const appName = notificationData?.appName || "?";
                        return appName.charAt(0).toUpperCase();
                    }

                    onImageStatusChanged: {
                        if (imageStatus === Image.Ready && needsImagePersist) {
                            const cachePath = NotificationService.getImageCachePath(notificationData);
                            saveImageToFile(cachePath);
                        }
                    }

                    onImageSaved: filePath => {
                        if (!notificationData)
                            return;
                        notificationData.persistedImagePath = filePath;
                        const wrapperId = notificationData.notification?.id?.toString() || "";
                        if (wrapperId)
                            NotificationService.updateHistoryImage(wrapperId, filePath);
                    }
                }

                Column {
                    id: textContainer

                    anchors.left: iconContainer.right
                    anchors.leftMargin: win.iconTextGap
                    anchors.right: parent.right
                    anchors.top: parent.top
                    // Short text blocks centre against the icon instead of hugging the top.
                    anchors.topMargin: Math.max(0, Math.round((win.popupIconSize - backgroundContainer.collapsedBlockHeight) / 2))
                    spacing: win.contentSpacing

                    // Header: bold title on the left, "app · time" on the right. Hovering
                    // swaps the meta text for the close button in the same corner.
                    Item {
                        id: headerRow
                        width: parent.width
                        height: win.titleLineHeight

                        StyledText {
                            id: summaryText
                            anchors.left: parent.left
                            anchors.right: metaBlock.left
                            anchors.rightMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            text: win.titleText
                            color: Theme.surfaceText
                            font.pixelSize: win.titleFontSize
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignLeft
                            maximumLineCount: 1
                        }

                        Item {
                            id: metaBlock
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: cardHoverHandler.hovered ? closeButton.width : Math.min(metaText.implicitWidth, Math.round(parent.width * 0.45))
                            height: parent.height

                            Behavior on width {
                                NumberAnimation {
                                    duration: Theme.shortDuration
                                    easing.type: Theme.standardEasing
                                }
                            }

                            StyledText {
                                id: metaText
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, parent.width)
                                text: win.metaText
                                color: Theme.surfaceTextMedium
                                font.pixelSize: win.metaFontSize
                                font.weight: Font.Normal
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignRight
                                maximumLineCount: 1
                                opacity: cardHoverHandler.hovered ? 0 : 1
                                visible: opacity > 0

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: Theme.shortDuration
                                        easing.type: Theme.standardEasing
                                    }
                                }
                            }

                            DankActionButton {
                                id: closeButton
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                iconName: "close"
                                iconSize: 14
                                buttonSize: 22
                                iconColor: Theme.surfaceTextMedium
                                opacity: cardHoverHandler.hovered ? 1 : 0
                                visible: opacity > 0
                                z: 15

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: Theme.shortDuration
                                        easing.type: Theme.standardEasing
                                    }
                                }

                                onClicked: {
                                    dismissPopupReliably();
                                }
                            }
                        }
                    }

                    StyledText {
                        id: bodyText
                        property bool hasMoreText: truncated

                        text: notificationData ? (notificationData.htmlBody || "") : ""
                        textFormat: Text.StyledText
                        color: Theme.surfaceVariantText
                        font.pixelSize: win.bodyFontSize
                        lineHeight: win.bodyLineRatio
                        lineHeightMode: Text.ProportionalHeight
                        width: parent.width
                        elide: win.descriptionExpanded ? Text.ElideNone : Text.ElideRight
                        horizontalAlignment: Text.AlignLeft
                        maximumLineCount: win.descriptionExpanded ? -1 : win.collapsedBodyLines
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        visible: text.length > 0 && !backgroundContainer.privacyCollapsed
                        linkColor: Theme.primary
                        onLinkActivated: link => Qt.openUrlExternally(link)

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: (parent.hoveredLink || win.bodyClickInvokesAction || bodyText.hasMoreText || win.descriptionExpanded) ? Qt.PointingHandCursor : Qt.ArrowCursor

                            onClicked: mouse => {
                                if (parent.hoveredLink || win.exiting)
                                    return;
                                if (win.bodyClickInvokesAction) {
                                    win.invokeDefaultAction();
                                    return;
                                }
                                if (bodyText.hasMoreText || win.descriptionExpanded)
                                    win.descriptionExpanded = !win.descriptionExpanded;
                            }

                            propagateComposedEvents: false
                            onPressed: mouse => {
                                if (parent.hoveredLink)
                                    mouse.accepted = false;
                            }
                            onReleased: mouse => {
                                if (parent.hoveredLink)
                                    mouse.accepted = false;
                            }
                        }
                    }

                    StyledText {
                        text: I18n.tr("Message Content", "notification privacy mode placeholder")
                        color: Theme.surfaceVariantText
                        font.pixelSize: win.bodyFontSize
                        font.italic: true
                        lineHeight: win.bodyLineRatio
                        lineHeightMode: Text.ProportionalHeight
                        width: parent.width
                        visible: backgroundContainer.privacyCollapsed && win.hasExpandableBody
                    }
                }
            }

            // Actions render as tonal pills under the text column, only when the app
            // sent any. No reserved row and no separate "Dismiss" button: the close
            // button, a click, or a swipe dismiss.
            Row {
                id: actionsRow
                visible: win.hasActions
                anchors.left: parent.left
                anchors.leftMargin: win.cardPaddingH + win.popupIconSize + win.iconTextGap
                anchors.top: notificationContent.bottom
                anchors.topMargin: win.actionRowGap
                spacing: Theme.spacingS
                z: 20

                Repeater {
                    model: notificationData ? (notificationData.actions || []) : []

                    Rectangle {
                        property bool isHovered: false

                        width: Math.max(actionText.implicitWidth + Theme.spacingM * 2, 56)
                        height: win.actionButtonHeight
                        radius: height / 2
                        color: isHovered ? Theme.withAlpha(Theme.primary, 0.22) : Theme.withAlpha(Theme.primary, 0.12)

                        Behavior on color {
                            ColorAnimation {
                                duration: Theme.shortDuration
                            }
                        }

                        StyledText {
                            id: actionText

                            text: modelData.text || "Open"
                            color: Theme.primary
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            anchors.centerIn: parent
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton
                            onEntered: parent.isHovered = true
                            onExited: parent.isHovered = false
                            onClicked: {
                                if (modelData && modelData.invoke)
                                    modelData.invoke();
                                dismissPopupReliably();
                            }
                        }
                    }
                }
            }

