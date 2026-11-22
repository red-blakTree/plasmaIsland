import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    // "" follows the system language; otherwise one of languageCodes below.
    property string cfg_language
    property string cfg_city
    property string cfg_stationId
    property string cfg_weatherProvider
    property string cfg_amapAdcode
    property alias cfg_amapKey: amapKeyField.text
    property alias cfg_showSeconds: secondsBox.checked
    property int cfg_clockFormat
    property int cfg_dateFormat
    property alias cfg_size: sizeBox.value
    property alias cfg_showTrackToast: toastBox.checked
    property alias cfg_customTimeFormat: customTimeField.text
    property alias cfg_customDateFormat: customDateField.text
    property alias cfg_transparentBackground: transparentBox.checked

    // City search: settingCity suppresses the text handler while the field is filled in code.
    property bool settingCity: false
    property bool searchDone: false
    property bool ready: false
    property int searchSeq: 0

    readonly property var languageCodes: ["", "en", "ru", "es", "de", "el", "zh_CN"]
    readonly property bool amapMode: cfg_weatherProvider === "amap"
    readonly property var loc: cfg_language === "" ? Qt.locale() : Qt.locale(cfg_language)

    // The page itself switches language as soon as one is chosen.
    Translator { id: t; language: page.cfg_language }

    // The combo boxes use ListModels whose labels are updated in place: replacing a plain
    // array model would reset their current index and clobber the saved choice.
    ListModel {
        id: languageModel
        ListElement { label: "" }
        ListElement { label: "English" }
        ListElement { label: "Русский" }
        ListElement { label: "Español" }
        ListElement { label: "Deutsch" }
        ListElement { label: "Ελληνικά" }
        ListElement { label: "简体中文" }
    }
    ListModel {
        id: providerModel
        ListElement { label: "中国气象局 (NMC)" }
        ListElement { label: "高德天气 (Amap)" }
    }
    ListModel {
        id: clockModel
        ListElement { label: "System default" }
        ListElement { label: "12-hour" }
        ListElement { label: "24-hour" }
        ListElement { label: "Custom" }
    }
    ListModel {
        id: dateModel
        ListElement { label: "" }
        ListElement { label: "" }
        ListElement { label: "" }
        ListElement { label: "" }
        ListElement { label: "" }
        ListElement { label: "" }
        ListElement { label: "" }
        ListElement { label: "" }
    }
    ListModel {
        id: cityResults
    }
    Timer {
        id: citySearchTimer
        interval: 300
        onTriggered: page.searchCities()
    }

    // A ComboBox keeps showing the old text of its current item when that item's label changes;
    // clearing and re-binding the index makes it read the new one.
    function refreshBox(box, valueFn) {
        box.currentIndex = -1;
        box.currentIndex = Qt.binding(valueFn);
    }

    function searchCities() {
        if (page.amapMode) {
            page.searchAmapCities();
        } else {
            page.searchNmcCities();
        }
    }

    function searchNmcCities() {
        const query = citySearch.text.trim();
        if (query === "") {
            cityResults.clear();
            page.searchDone = false;
            return;
        }
        const seq = ++page.searchSeq;
        const stamp = Date.now();
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE || seq !== page.searchSeq) {
                return;
            }
            cityResults.clear();
            page.searchDone = true;
            if (xhr.status !== 200) {
                return;
            }
            let data = null;
            try {
                data = JSON.parse(xhr.responseText);
            } catch (e) {
                return;
            }
            if (!data || data.code !== 0 || !Array.isArray(data.data)) {
                return;
            }
            for (const item of data.data) {
                const parts = typeof item === "string" ? item.split("|") : [];
                if (parts.length >= 6) {
                    cityResults.append({ stationId: parts[0], city: parts[1], province: parts[2] });
                }
            }
        };
        xhr.open("GET", "https://www.nmc.cn/essearch/api/autocomplete?q=" + encodeURIComponent(query)
                 + "&limit=10&timestamp=" + stamp + "&_=" + stamp);
        xhr.send();
    }

    function searchAmapCities() {
        const query = citySearch.text.trim();
        const key = amapKeyField.text.trim();
        cityResults.clear();
        page.searchDone = false;
        if (query === "" || key === "") {
            return;
        }
        const seq = ++page.searchSeq;
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE || seq !== page.searchSeq) {
                return;
            }
            cityResults.clear();
            page.searchDone = true;
            if (xhr.status !== 200) {
                return;
            }
            let data = null;
            try {
                data = JSON.parse(xhr.responseText);
            } catch (e) {
                return;
            }
            if (!data || data.status !== "1" || !Array.isArray(data.geocodes)) {
                return;
            }
            for (const geo of data.geocodes) {
                const adcode = page.amapText(geo.adcode);
                if (adcode === "") {
                    continue;
                }
                const province = page.amapText(geo.province);
                const cityName = page.amapText(geo.city);
                const district = page.amapText(geo.district);
                const name = district && district !== cityName ? district : (cityName || province
                    || page.amapText(geo.formatted_address));
                if (name === "") {
                    continue;
                }
                const region = cityName && cityName !== name ? cityName : province;
                cityResults.append({
                    stationId: adcode,
                    city: name,
                    province: region === name ? "" : region
                });
            }
        };
        xhr.open("GET", "https://restapi.amap.com/v3/geocode/geo?key=" + encodeURIComponent(key)
                 + "&address=" + encodeURIComponent(query));
        xhr.send();
    }

    // Amap mixes strings and empty arrays for missing fields.
    function amapText(v) {
        if (Array.isArray(v)) {
            return v.length > 0 ? String(v[0]) : "";
        }
        return v === undefined || v === null ? "" : String(v);
    }

    function selectCity(stationId, city) {
        page.settingCity = true;
        citySearch.text = city;
        page.settingCity = false;
        page.cfg_city = city;
        if (page.amapMode) {
            page.cfg_amapAdcode = stationId;
            page.cfg_stationId = "";
        } else {
            page.cfg_stationId = stationId;
            page.cfg_amapAdcode = "";
        }
        page.searchDone = false;
        page.searchSeq++;
        citySearchTimer.stop();
        cityResults.clear();
    }

    function retranslate() {
        const now = new Date();
        languageModel.setProperty(0, "label", t.tr("System default"));
        clockModel.setProperty(0, "label", t.tr("System default"));
        clockModel.setProperty(1, "label", t.tr("12-hour"));
        clockModel.setProperty(2, "label", t.tr("24-hour"));
        clockModel.setProperty(3, "label", t.tr("Custom"));
        const fmts = ["ddd, MMM d", "ddd, d MMM", "dd/MM/yyyy", "MM/dd/yyyy", "yyyy-MM-dd", "d MMMM yyyy"];
        for (let i = 0; i < fmts.length; i++) {
            dateModel.setProperty(i, "label", loc.toString(now, fmts[i]));
        }
        dateModel.setProperty(6, "label", t.tr("System short date") + " (" + loc.toString(now, Locale.ShortFormat) + ")");
        dateModel.setProperty(7, "label", t.tr("Custom"));
        refreshBox(languageBox, () => Math.max(0, page.languageCodes.indexOf(page.cfg_language)));
        refreshBox(clockBox, () => page.cfg_clockFormat);
        refreshBox(dateBox, () => page.cfg_dateFormat);
    }
    Component.onCompleted: {
        page.settingCity = true;
        citySearch.text = page.cfg_city;
        page.settingCity = false;
        page.ready = true;
        retranslate();
    }
    // Deferred: this handler can run before `t` and `loc` have picked up the new language.
    onCfg_languageChanged: Qt.callLater(retranslate)
    // Reflect external changes (e.g. the Reset button) while the field is not being edited.
    onCfg_cityChanged: {
        if (!page.ready || citySearch.activeFocus || citySearch.text === page.cfg_city) {
            return;
        }
        page.settingCity = true;
        citySearch.text = page.cfg_city;
        page.settingCity = false;
    }

    onCfg_weatherProviderChanged: {
        if (!page.ready) {
            return;
        }
        page.searchDone = false;
        page.searchSeq++;
        cityResults.clear();
        citySearchTimer.stop();
        if (citySearch.text.trim() !== ""
                && (!page.amapMode || amapKeyField.text.trim() !== "")) {
            citySearchTimer.restart();
        }
        providerBox.currentIndex = page.amapMode ? 1 : 0;
    }

    Kirigami.FormLayout {
        QQC2.ComboBox {
            id: languageBox
            Kirigami.FormData.label: t.tr("Language:")
            model: languageModel
            textRole: "label"
            currentIndex: Math.max(0, page.languageCodes.indexOf(page.cfg_language))
            onActivated: index => page.cfg_language = page.languageCodes[index]
        }

        QQC2.ComboBox {
            id: providerBox
            Kirigami.FormData.label: t.tr("Weather source:")
            model: providerModel
            textRole: "label"
            currentIndex: page.amapMode ? 1 : 0
            onActivated: index => page.cfg_weatherProvider = index === 1 ? "amap" : "nmc"
        }
        QQC2.TextField {
            id: amapKeyField
            visible: page.amapMode
            Kirigami.FormData.label: t.tr("Amap key:")
            placeholderText: "Web service key"
            onTextChanged: {
                if (!page.ready || !page.amapMode) {
                    return;
                }
                page.searchDone = false;
                page.searchSeq++;
                if (text.trim() === "" || citySearch.text.trim() === "") {
                    cityResults.clear();
                    citySearchTimer.stop();
                } else {
                    citySearchTimer.restart();
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Kirigami.FormData.label: t.tr("Weather city:")

            QQC2.TextField {
                id: citySearch
                Layout.fillWidth: true
                enabled: !page.amapMode || amapKeyField.text.trim() !== ""
                placeholderText: t.tr("Search a city…")
                onTextChanged: {
                    if (page.settingCity) {
                        return;
                    }
                    page.cfg_city = text;
                    page.cfg_stationId = "";
                    page.cfg_amapAdcode = "";
                    page.searchDone = false;
                    page.searchSeq++;
                    if (text.trim() === "") {
                        cityResults.clear();
                        citySearchTimer.stop();
                    } else {
                        citySearchTimer.restart();
                    }
                }
            }
            QQC2.Label {
                Layout.fillWidth: true
                visible: page.amapMode && amapKeyField.text.trim() === ""
                text: t.tr("Enter an Amap Web service key to search cities.")
                opacity: 0.7
                font: Kirigami.Theme.smallFont
                wrapMode: Text.WordWrap
            }
            QQC2.Label {
                Layout.fillWidth: true
                visible: page.searchDone && cityResults.count === 0
                text: t.tr("No matching city")
                opacity: 0.7
                font: Kirigami.Theme.smallFont
            }
            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(cityResults.count, 5) * Kirigami.Units.gridUnit * 2
                visible: cityResults.count > 0
                clip: true
                model: cityResults
                delegate: QQC2.ItemDelegate {
                    required property string stationId
                    required property string city
                    required property string province
                    width: ListView.view.width
                    text: province ? city + " · " + province : city
                    highlighted: page.amapMode
                        ? page.cfg_amapAdcode === stationId
                        : page.cfg_stationId === stationId
                    onClicked: page.selectCity(stationId, city)
                }
            }
            QQC2.Label {
                Layout.fillWidth: true
                text: t.tr("Without a city, the pill shows “Set city” instead of the temperature.")
                opacity: 0.7
                font: Kirigami.Theme.smallFont
                wrapMode: Text.WordWrap
            }
        }
        QQC2.SpinBox {
            id: sizeBox
            Kirigami.FormData.label: t.tr("Size:")
            from: 16
            to: 72
            stepSize: 2
            textFromValue: (value, locale) => t.tr("%1 px", value)
            valueFromText: (text, locale) => parseInt(text) || 32
        }
        QQC2.Label {
            text: t.tr("Tip: hold Ctrl and scroll over the pill to resize it live.")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }
        QQC2.CheckBox {
            id: transparentBox
            Kirigami.FormData.label: t.tr("Background:")
            text: t.tr("Transparent (text only, in the panel's colours)")
        }
        QQC2.CheckBox {
            id: secondsBox
            Kirigami.FormData.label: t.tr("Clock:")
            text: t.tr("Show seconds")
        }
        QQC2.ComboBox {
            id: clockBox
            Kirigami.FormData.label: t.tr("Time format:")
            model: clockModel
            textRole: "label"
            currentIndex: page.cfg_clockFormat
            onActivated: index => page.cfg_clockFormat = index
        }
        QQC2.TextField {
            id: customTimeField
            visible: page.cfg_clockFormat === 3
            Kirigami.FormData.label: t.tr("Custom format:")
            placeholderText: "HH:mm"
        }
        QQC2.Label {
            visible: customTimeField.visible
            text: t.tr("Preview: %1", page.loc.toString(new Date(), customTimeField.text.trim() || "HH:mm"))
                  + "\n" + t.tr("H/HH hours (24h), h/hh hours (12h), mm minutes, ss seconds, AP am/pm")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }
        QQC2.ComboBox {
            id: dateBox
            Kirigami.FormData.label: t.tr("Date format:")
            model: dateModel
            textRole: "label"
            currentIndex: page.cfg_dateFormat
            onActivated: index => page.cfg_dateFormat = index
        }
        QQC2.TextField {
            id: customDateField
            visible: page.cfg_dateFormat === 7
            Kirigami.FormData.label: t.tr("Custom format:")
            placeholderText: "yyyy-MM-dd"
        }
        QQC2.Label {
            visible: customDateField.visible
            text: t.tr("Preview: %1", page.loc.toString(new Date(), customDateField.text.trim() || "yyyy-MM-dd"))
                  + "\n" + t.tr("d/dd day, ddd/dddd weekday, M/MM/MMM/MMMM month, yy/yyyy year")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }
        QQC2.CheckBox {
            id: toastBox
            Kirigami.FormData.label: t.tr("Music:")
            text: t.tr("Briefly show each new track in the pill")
        }
    }
}
