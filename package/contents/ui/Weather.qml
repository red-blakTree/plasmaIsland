import QtQuick

// Weather from the National Meteorological Center of China (https://www.nmc.cn) by
// default, or from Amap (https://lbs.amap.com) when a Web service key is configured.
// NMC needs no key and refreshes every 15 minutes; Amap refreshes every 30 minutes.
Item {
    id: weather

    property string city: ""
    property string stationId: ""     // an NMC station chosen in the settings (optional)
    property string provider: "nmc"     // "nmc" or "amap"
    property string amapKey: ""
    property string amapAdcode: ""
    property string resolvedAmapAdcode: ""
    readonly property bool amapSelected: provider === "amap"
    readonly property bool hasCity: amapSelected
        ? amapKey.trim() !== "" && (amapAdcode !== "" || city.trim() !== "")
        : city.trim() !== "" || stationId !== ""
    readonly property bool imperial: Qt.locale().measurementSystem === Locale.ImperialUSSystem

    // NaN until the first successful fetch, or when no city is set.
    property real temperature: NaN
    property real feelsLike: NaN
    property real high: NaN
    property real low: NaN
    property int humidity: -1
    property real windSpeed: NaN
    property string windText: ""       // Amap reports wind as text (direction + force)
    readonly property string windUnit: imperial ? "mph" : "km/h"
    property string condition: ""     // msgid for t.tr(), or the server's own text
    property string iconName: "weather-none-available"
    property string placeName: ""
    // [{ time: Date, high, low, iconName }]
    property var daily: []
    property string resolvedStationId: ""

    readonly property bool available: !isNaN(temperature)
    // True after a failed lookup or fetch (no network, unknown city), until the next success.
    property bool failed: false
    readonly property string text: available ? deg(temperature) : "—"

    function deg(t) {
        if (isNaN(t)) {
            return "—";
        }
        return Math.round(imperial ? t * 9 / 5 + 32 : t) + "°";
    }

    function resetWeather() {
        placeName = "";
        temperature = NaN;
        feelsLike = NaN;
        high = NaN;
        low = NaN;
        humidity = -1;
        windSpeed = NaN;
        windText = "";
        daily = [];
        failed = false;
        iconName = "weather-none-available";
    }

    onCityChanged: {
        resolvedStationId = stationId;
        resolvedAmapAdcode = amapAdcode;
        resetWeather();
        soon.restart();
    }
    onStationIdChanged: {
        resolvedStationId = stationId;
        soon.restart();
    }
    onAmapAdcodeChanged: {
        resolvedAmapAdcode = amapAdcode;
        soon.restart();
    }
    onAmapKeyChanged: soon.restart()
    onProviderChanged: {
        resolvedStationId = stationId;
        resolvedAmapAdcode = amapAdcode;
        resetWeather();
        soon.restart();
    }
    onImperialChanged: soon.restart()
    Component.onCompleted: {
        resolvedStationId = stationId;
        resolvedAmapAdcode = amapAdcode;
        soon.restart();
    }

    // Collapses the startup/config-change triggers above into a single request.
    Timer {
        id: soon
        interval: 300
        onTriggered: weather.refresh()
    }

    Timer {
        interval: weather.amapSelected ? 30 * 60 * 1000 : 15 * 60 * 1000
        running: weather.hasCity
        repeat: true
        onTriggered: weather.refresh()
    }

    // Retry sooner after a failure (no network at login, for example).
    Timer {
        id: retry
        interval: weather.amapSelected ? 5 * 60 * 1000 : 60 * 1000
        onTriggered: weather.refresh()
    }

    function getJson(url, onDone) {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) {
                return;
            }
            let data = null;
            if (xhr.status === 200) {
                try {
                    data = JSON.parse(xhr.responseText);
                } catch (e) {
                    data = null;
                }
            }
            onDone(data);
        };
        xhr.open("GET", url);
        xhr.send();
    }

    function refresh() {
        if (amapSelected) {
            refreshAmap();
            return;
        }
        const name = city.trim();
        if (name === "" && resolvedStationId === "") {
            return;
        }
        if (resolvedStationId === "") {
            const requested = name;
            const stamp = Date.now();
            getJson("https://www.nmc.cn/essearch/api/autocomplete?q=" + encodeURIComponent(name)
                    + "&limit=10&timestamp=" + stamp + "&_=" + stamp, data => {
                if (requested !== weather.city.trim()) {
                    return; // the city changed while we were waiting
                }
                const hit = data && data.code === 0 && data.data ? data.data[0] : null;
                const parts = typeof hit === "string" ? hit.split("|") : [];
                if (parts.length < 6) {
                    weather.failed = true;
                    retry.restart();
                    return;
                }
                weather.resolvedStationId = parts[0];
                weather.fetchForecast();
            });
        } else {
            fetchForecast();
        }
    }

    function fetchForecast() {
        const requested = resolvedStationId;
        getJson("https://www.nmc.cn/rest/weather?stationid=" + encodeURIComponent(requested)
                + "&_=" + Date.now(), data => {
            if (requested !== weather.resolvedStationId) {
                return; // the city changed while we were waiting
            }
            const d = data && data.code === 0 ? data.data : null;
            const real = d && d.real;
            const current = real && real.weather;
            if (!current || isNaN(toNumber(current.temperature))) {
                weather.failed = true;
                retry.restart();
                return;
            }
            weather.failed = false;
            weather.temperature = toNumber(current.temperature);
            weather.feelsLike = toNumber(current.feelst);
            const humidity = toNumber(current.humidity);
            weather.humidity = isNaN(humidity) ? -1 : Math.round(humidity);

            const wind = real.wind;
            const windSpeed = wind ? toNumber(wind.speed) : NaN;
            weather.windSpeed = isNaN(windSpeed) ? NaN : windSpeed * (weather.imperial ? 2.236936 : 3.6);

            const station = real.station || {};
            const province = station.province || "";
            weather.placeName = station.city
                ? (province && province !== station.city + "市" ? station.city + ", " + province : station.city)
                : "";

            const sun = real.sunriseSunset || {};
            const night = isNight(sun.sunrise, sun.sunset);

            const detail = d.predict && Array.isArray(d.predict.detail) ? d.predict.detail : [];
            const today = detail[0];
            let img = current.img;
            if (!isValidImg(img) && today) {
                const part = night ? today.night : today.day;
                img = part && part.weather ? part.weather.img : "";
            }
            weather.condition = conditionFor(img, current.info);
            weather.iconName = iconFor(img, night);

            weather.high = today && today.day && today.day.weather
                ? toNumber(today.day.weather.temperature) : NaN;
            weather.low = today && today.night && today.night.weather
                ? toNumber(today.night.weather.temperature) : NaN;
            if (isNaN(weather.high) || isNaN(weather.low)) {
                const chart = d.tempchart;
                if (Array.isArray(chart) && chart.length > 0) {
                    const last = chart[chart.length - 1];
                    weather.high = isNaN(weather.high) ? toNumber(last.max_temp) : weather.high;
                    weather.low = isNaN(weather.low) ? toNumber(last.min_temp) : weather.low;
                }
            }

            // Today is already in the header; the row shows the next six days.
            const days = [];
            for (let i = 1; i < detail.length && days.length < 6; i++) {
                const entry = detail[i];
                const day = entry.day && entry.day.weather;
                if (!day || isNaN(toNumber(day.temperature))) {
                    continue;
                }
                days.push({
                    time: parseDate(entry.date),
                    high: toNumber(day.temperature),
                    low: entry.night && entry.night.weather ? toNumber(entry.night.weather.temperature) : NaN,
                    iconName: iconFor(day.img, false)
                });
            }
            weather.daily = days;
        });
    }

    // --- Amap (高德) ------------------------------------------------------
    // Amap returns live conditions and a four-day forecast in two requests. The city is
    // an adcode, resolved from the typed name with Amap's geocoder when the settings
    // did not already store one.

    function refreshAmap() {
        const key = amapKey.trim();
        if (key === "" || !hasCity) {
            return;
        }
        if (resolvedAmapAdcode !== "") {
            fetchAmapWeather();
            return;
        }
        const requested = city.trim();
        if (requested === "") {
            return;
        }
        getJson("https://restapi.amap.com/v3/geocode/geo?key=" + encodeURIComponent(key)
                + "&address=" + encodeURIComponent(requested), data => {
            if (!amapSelected || requested !== weather.city.trim()) {
                return; // the city changed while we were waiting
            }
            if (!data) {
                weather.failed = true;
                retry.restart();
                return;
            }
            if (data.status !== "1") {
                weather.failed = true; // invalid key or quota: retrying won't help
                return;
            }
            const hits = Array.isArray(data.geocodes) ? data.geocodes : [];
            const hit = hits.find(g => amapText(g.adcode) !== "");
            if (!hit) {
                weather.failed = true;
                retry.restart();
                return;
            }
            weather.resolvedAmapAdcode = amapText(hit.adcode);
            weather.fetchAmapWeather();
        });
    }

    function fetchAmapWeather() {
        const requested = resolvedAmapAdcode;
        const key = amapKey.trim();
        if (requested === "" || key === "") {
            return;
        }
        getJson("https://restapi.amap.com/v3/weather/weatherInfo?key=" + encodeURIComponent(key)
                + "&city=" + encodeURIComponent(requested) + "&extensions=base", data => {
            if (!amapSelected || requested !== weather.resolvedAmapAdcode) {
                return;
            }
            if (!data) {
                weather.failed = true;
                retry.restart();
                return;
            }
            if (data.status !== "1") {
                weather.failed = true; // invalid key or quota: retrying won't help
                return;
            }
            const live = Array.isArray(data.lives) ? data.lives[0] : null;
            if (!live || isNaN(toNumber(live.temperature))) {
                weather.failed = true;
                retry.restart();
                return;
            }
            weather.failed = false;
            weather.temperature = toNumber(live.temperature);
            weather.feelsLike = NaN;
            const humidity = toNumber(live.humidity);
            weather.humidity = isNaN(humidity) ? -1 : Math.round(humidity);
            weather.windSpeed = NaN;
            const direction = amapText(live.winddirection);
            const power = amapText(live.windpower);
            weather.windText = (direction && direction !== "无风向" ? direction + "风 " : "")
                + (power ? power + "级" : "");
            const province = amapText(live.province);
            const cityName = amapText(live.city);
            weather.placeName = cityName
                ? (province && province !== cityName ? cityName + ", " + province : cityName)
                : province;
            const text = amapText(live.weather);
            weather.condition = conditionForAmap(text);
            weather.iconName = iconForAmap(text, isDaytime());
            weather.fetchAmapForecast();
        });
    }

    function fetchAmapForecast() {
        const requested = resolvedAmapAdcode;
        const key = amapKey.trim();
        if (requested === "" || key === "") {
            return;
        }
        getJson("https://restapi.amap.com/v3/weather/weatherInfo?key=" + encodeURIComponent(key)
                + "&city=" + encodeURIComponent(requested) + "&extensions=all", data => {
            if (!amapSelected || requested !== weather.resolvedAmapAdcode) {
                return;
            }
            const forecast = data && data.status === "1" && Array.isArray(data.forecasts)
                ? data.forecasts[0] : null;
            const casts = forecast && Array.isArray(forecast.casts) ? forecast.casts : [];
            if (casts.length === 0) {
                weather.daily = [];
                return;
            }
            const today = casts[0];
            weather.high = toNumber(today.daytemp);
            weather.low = toNumber(today.nighttemp);
            const days = [];
            for (let i = 1; i < casts.length && days.length < 6; i++) {
                const cast = casts[i];
                days.push({
                    time: parseDate(cast.date),
                    high: toNumber(cast.daytemp),
                    low: toNumber(cast.nighttemp),
                    iconName: iconForAmap(amapText(cast.dayweather), false)
                });
            }
            weather.daily = days;
        });
    }

    // Amap mixes strings and empty arrays for missing fields.
    function amapText(v) {
        if (Array.isArray(v)) {
            return v.length > 0 ? String(v[0]) : "";
        }
        return v === undefined || v === null ? "" : String(v);
    }

    function isDaytime() {
        const h = new Date().getHours();
        return h >= 6 && h < 18;
    }

    // The API uses numbers, numeric strings and "9999" for missing values.
    function toNumber(v) {
        if (typeof v === "number") {
            return isFinite(v) && v !== 9999 ? v : NaN;
        }
        if (typeof v === "string" && v !== "" && v !== "9999") {
            const n = Number(v);
            return isFinite(n) ? n : NaN;
        }
        return NaN;
    }

    function isValidImg(img) {
        return img !== undefined && img !== null && img !== "" && String(img) !== "9999";
    }

    // "2026-11-15 06:58" and "2026-11-15" are local to the city.
    function parseDateTime(s) {
        const m = /^(\d+)-(\d+)-(\d+) (\d+):(\d+)/.exec(s || "");
        return m ? new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5]) : new Date(NaN);
    }

    function parseDate(s) {
        const m = /^(\d+)-(\d+)-(\d+)/.exec(s || "");
        return m ? new Date(+m[1], +m[2] - 1, +m[3]) : new Date(NaN);
    }

    function isNight(sunrise, sunset) {
        const rise = parseDateTime(sunrise);
        const set = parseDateTime(sunset);
        if (isNaN(rise) || isNaN(set)) {
            return false;
        }
        const now = new Date();
        return now < rise || now >= set;
    }

    // NMC weather icon codes, mapped to the widget's condition strings.
    function conditionFor(img, info) {
        switch (String(img)) {
        case "0": return "Clear";
        case "1": return "Partly cloudy";
        case "2": return "Overcast";
        case "3": return "Showers";
        case "4": case "9": case "10": return "Thunderstorm";
        case "5": return "Thunderstorm with hail";
        case "6": return "Rain and snow";
        case "7": case "8": case "21": return "Rain";
        case "11": case "12": case "22": case "23": case "24": case "25": return "Heavy rain";
        case "13": return "Snow showers";
        case "14": case "15": case "26": return "Snow";
        case "16": case "17": case "27": case "28": return "Heavy snow";
        case "18": case "32": case "49": case "57": case "58": return "Fog";
        case "19": return "Freezing rain";
        case "20": case "29": case "30": case "31": return "Dust";
        case "53": case "54": case "55": case "56": return "Haze";
        case "301": return "Rain";
        case "302": return "Snow";
        default: return info && info !== "-" && info !== "9999" ? info : "";
        }
    }

    // NMC weather icon codes, mapped to Breeze icon names.
    function iconFor(img, night) {
        switch (String(img)) {
        case "0": return night ? "weather-clear-night" : "weather-clear";
        case "1": return night ? "weather-few-clouds-night" : "weather-few-clouds";
        case "2": return "weather-overcast";
        case "3": return "weather-showers-scattered";
        case "4": case "5": case "9": case "10": return "weather-storm";
        case "6": return "weather-freezing-rain";
        case "7": case "8": case "21": return "weather-showers";
        case "11": case "12": case "22": case "23": case "24": case "25": return "weather-showers";
        case "13": return "weather-snow-scattered";
        case "14": case "15": case "26": return "weather-snow";
        case "16": case "17": case "27": case "28": return "weather-snow";
        case "18": case "32": case "49": case "57": case "58": return "weather-fog";
        case "19": return "weather-freezing-rain";
        case "53": case "54": case "55": case "56": return "weather-fog";
        case "301": return "weather-showers";
        case "302": return "weather-snow";
        default: return "weather-none-available";
        }
    }

    // Amap weather text, mapped to the widget's condition strings.
    function conditionForAmap(text) {
        const s = String(text || "");
        if (s === "" || s === "未知") {
            return "";
        }
        if (s.indexOf("雨夹雪") >= 0 || s.indexOf("雨雪") >= 0 || s.indexOf("阵雨夹雪") >= 0) {
            return "Rain and snow";
        }
        if (s.indexOf("冻雨") >= 0) {
            return "Freezing rain";
        }
        if (s.indexOf("雷") >= 0) {
            return s.indexOf("冰雹") >= 0 ? "Thunderstorm with hail" : "Thunderstorm";
        }
        if (s.indexOf("雪") >= 0) {
            if (s.indexOf("暴雪") >= 0 || s.indexOf("大雪") >= 0) {
                return "Heavy snow";
            }
            return s.indexOf("阵雪") >= 0 ? "Snow showers" : "Snow";
        }
        if (s.indexOf("雨") >= 0) {
            if (s.indexOf("暴雨") >= 0 || s.indexOf("大雨") >= 0 || s.indexOf("极端") >= 0) {
                return "Heavy rain";
            }
            return s.indexOf("阵雨") >= 0 ? "Showers" : "Rain";
        }
        if (s.indexOf("霾") >= 0) {
            return "Haze";
        }
        if (s.indexOf("沙") >= 0 || s.indexOf("尘") >= 0) {
            return "Dust";
        }
        if (s.indexOf("雾") >= 0) {
            return "Fog";
        }
        if (s.indexOf("晴间多云") >= 0 || s.indexOf("多云") >= 0 || s.indexOf("少云") >= 0) {
            return "Partly cloudy";
        }
        if (s.indexOf("阴") >= 0) {
            return "Overcast";
        }
        if (s.indexOf("晴") >= 0) {
            return "Clear";
        }
        if (s.indexOf("平静") >= 0) {
            return "Clear";
        }
        if (s.indexOf("风") >= 0 || s.indexOf("龙卷") >= 0) {
            return "Windy";
        }
        return s;
    }

    // Amap weather text, mapped to Breeze icon names.
    function iconForAmap(text, night) {
        switch (conditionForAmap(text)) {
        case "Clear": return night ? "weather-clear-night" : "weather-clear";
        case "Partly cloudy": return night ? "weather-few-clouds-night" : "weather-few-clouds";
        case "Overcast": return "weather-overcast";
        case "Showers": return "weather-showers-scattered";
        case "Thunderstorm": case "Thunderstorm with hail": return "weather-storm";
        case "Rain and snow": case "Freezing rain": return "weather-freezing-rain";
        case "Rain": case "Heavy rain": return "weather-showers";
        case "Snow showers": return "weather-snow-scattered";
        case "Snow": case "Heavy snow": return "weather-snow";
        case "Fog": case "Haze": case "Dust": return "weather-fog";
        case "Windy": return "weather-few-clouds";
        default: return "weather-none-available";
        }
    }
}
