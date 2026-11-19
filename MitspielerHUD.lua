-- FS25_CoworkerHUD (Build 57) - OGW
--
-- Oben neben der Uhrzeit: was die Mitspieler des eigenen Hofs geladen
-- haben. Unter dem Tacho: Gewicht, Kilometerstand und Motorlast des
-- eigenen Gespanns. Dazu ein Warnton, wenn der Diesel knapp wird.
-- Laeuft Farm Economy mit, steht dessen Verbrauch im Zifferblatt.
--
-- Reine Anzeige - keine Events, nichts im Spielstand.
--
-- Alles haengt am Zifferblatt des Spiels (hud.speedMeter.speedBg) und
-- rechnet in dessen 232er-Pixelraster. Damit sitzt das Layout auch bei
-- anderer UI-Groesse und auf Ultrawide richtig.
--
-- Testmodus ohne Mitspieler: Konsole, "mhudTest".

local modDirectory = g_currentModDirectory or ""

MitspielerHUD = {
    updateTimer = 0,
    lines = {},
    topEntries = {},      -- kompakte Eintraege fuer die obere Leiste
    ownKm = nil,          -- Kilometerstand des eigenen Fahrzeugs (Zahl)
    ownLoadText = nil,    -- Motorlast, z.B. "Last 46 %"
    ownMassOwn = nil,     -- Gewicht der Zugmaschine (Zahl, t)
    ownMassRig = nil,     -- Gewicht des Angehaengten inkl. Ladung (Zahl, t; nil = nichts dran)
    ownFuelPercent = nil, -- Diesel-Fuellstand 0..1 des eigenen Fahrzeugs
    fuelWarnCooldown = 0, -- ms bis zum naechsten Warnton
    warnSampleId = nil,   -- Engine-Sample des Warntons
    anchorLogged = false,
    barLayoutLogged = false,
    testMode = false,     -- Konsole "mhudTest": unbesetzte Hof-Fahrzeuge
                          -- werden wie Mitspieler angezeigt (zum Testen)
    consoleRegistered = false,

    -- Tank-Warnung
    FUEL_WARN_THRESHOLD = 0.10,   -- warnen unter 10 %
    FUEL_WARN_REPEAT_MS = 30000,  -- Wiederholung alle 30 s
    FUEL_WARN_VOLUME    = 0.7,

    -- Ab diesem Fuellstand (Prozent) wird eine Ladungs-Angabe ROT
    -- dargestellt (fast voll -> abtanken!)
    FILL_WARN_PERCENT = 95,
    -- Bei AUSBRINGENDEN Geraeten (Guellefass, Miststreuer, Kalk-/
    -- Duengerstreuer, Saemaschine, Futtermischwagen) gilt es
    -- umgekehrt: ROT, wenn nur noch so wenig Prozent drin sind
    FILL_WARN_LOW_PERCENT = 15,

    -- Leere Behaelter werden mit angezeigt (man sieht, wer noch Platz
    -- hat). Kleine Nebentanks - Siliermittel, Reiniger und dergleichen -
    -- aber nur, wenn wirklich etwas drin ist: sonst steht in der Leiste
    -- mehr Nebensache als Ladung.
    EMPTY_MIN_CAPACITY = 200,

    -- Liter-Anzeige UEBER dem Tank-Balken (232er-Referenzpixel).
    -- Zwischen Balken-Oberkante und Tank-Symbol liegen rund 14 px;
    -- der Text wird MITTIG in diese Luecke gesetzt, also mit Luft
    -- nach oben (Symbol) und unten (Balken).
    FUEL_TEXT_PX       = 11,  -- Textgroesse (Luecke ist nur ~14 px hoch)
    FUEL_GAP_PX        = 14,  -- Hoehe der Luecke Balken <-> Symbol
    FUEL_TEXT_SHIFT_PX = 0,   -- Feinjustierung senkrecht (+ = nach oben)
    FUEL_TEXT_OFFSET_X_PX = 0,-- Feinzentrierung waagerecht (+ = nach rechts)

    -- Einstellbare Konstanten
    UPDATE_INTERVAL = 1000,  -- ms zwischen zwei Datensammlungen
    MAX_PLAYERS     = 6,     -- max. angezeigte Mitspieler
    MAX_DEPTH       = 4,     -- max. Anhaenger-Kette (Traktor->HW80->HW80...)

    -- Mitspieler-Panel (232er-Referenzpixel des Zifferblatts)
    PANEL_HEAD_PX   = 17,   -- Textgroesse Kopfzeile (Spieler | Fahrzeug)
    PANEL_SUB_PX    = 15,   -- Textgroesse Fuellstands-Zeilen
    PANEL_PAD_X_PX  = 12,   -- Innenabstand links/rechts
    PANEL_PAD_Y_PX  = 9,    -- Innenabstand oben/unten
    PANEL_INDENT_PX = 14,   -- Einrueckung der Fuellstands-Zeilen
    PANEL_GAP_PX    = 5,    -- Abstand zum Element darunter
    PANEL_CAP_PX    = 8,    -- Breite der seitlichen Endkappen
    PANEL_BLOCK_PX  = 6,    -- Zusatzabstand zwischen zwei Mitspielern

    -- Info-Leiste unter dem Tacho (232er-Referenzpixel des Zifferblatts)
    BAR_H_PX    = 26,   -- Hoehe der Leiste
    BAR_GAP_PX  = 3,    -- Abstand zur Tacho-Unterkante
    BAR_PAD_PX  = 10,   -- Innenabstand links/rechts
    BAR_TEXT_PX = 16,   -- Textgroesse in der Leiste
    BAR_CAP_PX  = 6,    -- Breite der runden Endkappen
    BAR_MIN_Y   = 0.004,-- unterster erlaubter Rand am Bildschirm
    BAR_MIN_SCALE = 0.8,-- nur leicht schrumpfen, sonst lieber nach oben
                        -- ausweichen (kleine Schrift wird unleserlich)

    -- Spritverbrauch IM Zifferblatt, unter der KM/H-Anzeige
    -- ("KM/H"-Unterkante -27 px, Betriebsstunden-Trennlinie -43 px).
    -- Gleiche Werte, die Farm Economy ohne diese Mod selbst nutzt.
    ODO_DIAL_PX   = 11,     -- Textgroesse
    ODO_DIAL_Y_PX = -39,    -- Baseline ab Dial-Mitte (dicht unter "KM/H";
                            -- moeglich bis -27 - ODO_DIAL_PX, sonst Ueberlappung)
}

-- Diese Fuelltypen sind Fahrzeug-Betriebsstoffe und keine Ladung
local EXCLUDED_FILLTYPES = {
    DIESEL = true,
    DEF = true,
    AIR = true,
    ELECTRICCHARGE = true,
    METHANE = true,
}

-- Was ausgebracht wird, zaehlt rueckwaerts: voll ist normal, leer
-- heisst nachladen. Gilt auch fuer Fronttanks - die sind selbst keine
-- Ausbringer, ihr Inhalt ist trotzdem Nachschub.
local SUPPLY_FILLTYPES = {
    SEEDS = true,
    FERTILIZER = true,
    LIQUIDFERTILIZER = true,
    HERBICIDE = true,
    LIME = true,
    MANURE = true,
    LIQUIDMANURE = true,
    DIGESTATE = true,
    WATER = true,
    MINERAL_FEED = true,
    ROADSALT = true,
}

-- ------------------------------------------------------------
-- Hilfsfunktionen (alle defensiv, duerfen nie crashen)
-- ------------------------------------------------------------

-- Uebersetzten Text holen (modDesc <l10n>), mit Fallback
local function getLocText(name, fallback)
    if g_i18n ~= nil and g_i18n.getText ~= nil then
        local t = g_i18n:getText(name)
        if t ~= nil and t ~= "" and t ~= name then
            return t
        end
    end
    return fallback
end

local function getMyFarmId()
    if g_currentMission ~= nil then
        if g_currentMission.getFarmId ~= nil then
            local id = g_currentMission:getFarmId()
            if id ~= nil then
                return id
            end
        end
        if g_localPlayer ~= nil and g_localPlayer.farmId ~= nil then
            return g_localPlayer.farmId
        end
    end
    return nil
end

local function getFillTypeName(ftIndex)
    if ftIndex ~= nil and g_fillTypeManager ~= nil
        and g_fillTypeManager.getFillTypeNameByIndex ~= nil then
        local name = g_fillTypeManager:getFillTypeNameByIndex(ftIndex)
        if name ~= nil then
            return name
        end
    end
    return "UNKNOWN"
end

local function getFillTypeTitle(ftIndex)
    if ftIndex ~= nil and g_fillTypeManager ~= nil then
        if g_fillTypeManager.getFillTypeTitleByIndex ~= nil then
            local title = g_fillTypeManager:getFillTypeTitleByIndex(ftIndex)
            if title ~= nil then
                return title
            end
        end
        if g_fillTypeManager.getFillTypeByIndex ~= nil then
            local ft = g_fillTypeManager:getFillTypeByIndex(ftIndex)
            if ft ~= nil and ft.title ~= nil then
                return ft.title
            end
        end
    end
    return "?"
end

local function formatLiters(value)
    value = math.floor((value or 0) + 0.5)
    if g_i18n ~= nil and g_i18n.formatNumber ~= nil then
        local text = g_i18n:formatNumber(value, 0)
        if text ~= nil then
            return text
        end
    end
    return tostring(value)
end

-- Tankstand 0..1 ueber dieselbe Funktion wie der Spiel-Tacho, findet
-- auch Elektro und Methan. Die drei Getter dahinter gibt es nur mit
-- Motorized und FillUnit, also vorher nachsehen.
local function getFuelPercent(vehicle)
    if vehicle ~= nil and SpeedMeterDisplay ~= nil
        and SpeedMeterDisplay.getVehicleFuelLevelAndCapacity ~= nil
        and vehicle.getConsumerFillUnitIndex ~= nil
        and vehicle.getFillUnitFillLevel ~= nil
        and vehicle.getFillUnitCapacity ~= nil then
        local level, capacity =
            SpeedMeterDisplay.getVehicleFuelLevelAndCapacity(vehicle)
        if level ~= nil and capacity ~= nil and capacity > 0 then
            return level / capacity, level
        end
    end
    return nil, nil
end

-- Seitenverhaeltnis des Bildschirms (16:9 = 1.778, Ultrawide 32:9 = 3.556)
local function getAspect()
    if g_screenWidth ~= nil and g_screenHeight ~= nil and g_screenHeight > 0 then
        return g_screenWidth / g_screenHeight
    end
    if g_screenAspectRatio ~= nil and g_screenAspectRatio > 0 then
        return g_screenAspectRatio
    end
    return 16 / 9
end

-- Textbreite, mit Notloesung falls getTextWidth fehlt
local function textWidth(size, text)
    if getTextWidth ~= nil then
        local w = getTextWidth(size, text)
        if w ~= nil then
            return w
        end
    end
    return #text * size * 0.55
end

-- Textfarbe fuer Beschriftungen im Tacho: dasselbe Gruen, das das Spiel
-- fuer "KM/H", Betriebsstunden-Symbol und Tempomat nutzt
local function setActiveTextColor()
    local r, g, b, a = 0.62, 0.86, 0.17, 1.0
    if HUD ~= nil and HUD.COLOR ~= nil and HUD.COLOR.ACTIVE ~= nil then
        r, g, b, a = unpack(HUD.COLOR.ACTIVE)
    end
    setTextColor(r, g, b, a)
end

-- Geraete, die ihre Ladung beim Arbeiten loswerden - hier warnt Rot
-- bei fast leer statt bei fast voll.
local function isDispenser(vehicle)
    return vehicle.spec_sprayer ~= nil            -- Guelle/Duenger/Kalk/Mist
        or vehicle.spec_manureBarrel ~= nil
        or vehicle.spec_sowingMachine ~= nil      -- Saemaschinen
        or vehicle.spec_mixerWagon ~= nil         -- Futtermischwagen
end

-- Rot heisst: hier ist was zu tun. Ladung fast voll -> abfahren,
-- Nachschub fast leer -> nachfuellen. Ob Nachschub, verraet entweder
-- das Geraet oder der Inhalt; ohne den zweiten Weg stand ein voller
-- Fronttank faelschlich auf Rot.
local function getFillWarn(vehicle, percent, fillTypeName)
    if isDispenser(vehicle) or SUPPLY_FILLTYPES[fillTypeName] ~= nil then
        return percent <= MitspielerHUD.FILL_WARN_LOW_PERCENT
    end
    return percent >= MitspielerHUD.FILL_WARN_PERCENT
end

-- Laeuft das Gespann einmal durch und baut daraus die Teile
-- "Weizen 12.500 / 18.000 l (69%)" bzw. "Leer 0 / 18.000 l (0%)".
--   out   (optional) Zeilen fuers Ersatz-Panel
--   parts (optional) kompakte Teile fuer die obere Leiste
local function collectRigFill(vehicle, out, parts, depth)
    if vehicle == nil or depth > MitspielerHUD.MAX_DEPTH then
        return
    end

    if vehicle.getFillUnits ~= nil
        and vehicle.getFillUnitCapacity ~= nil
        and vehicle.getFillUnitFillLevel ~= nil then
        local fillUnits = vehicle:getFillUnits()
        if fillUnits ~= nil then
            for i = 1, #fillUnits do
                local capacity = vehicle:getFillUnitCapacity(i) or 0
                if capacity > 0 then
                    local level = vehicle:getFillUnitFillLevel(i) or 0
                    local ftIndex = nil
                    if vehicle.getFillUnitFillType ~= nil then
                        ftIndex = vehicle:getFillUnitFillType(i)
                    end
                    -- Leere Kleintanks (Siliermittel & Co.) weglassen
                    local zeige = level >= 1
                        or capacity >= MitspielerHUD.EMPTY_MIN_CAPACITY
                    local ftName = getFillTypeName(ftIndex)
                    if zeige and EXCLUDED_FILLTYPES[ftName] == nil then
                        local percent = math.floor(level / capacity * 100 + 0.5)
                        local warn = getFillWarn(vehicle, percent, ftName)
                        local title
                        if level >= 1 then
                            title = getFillTypeTitle(ftIndex)
                        else
                            title = MitspielerHUD.txtEmpty or "leer"
                            title = title:sub(1, 1):upper() .. title:sub(2)
                            level = 0  -- Restmengen unter 1 l nicht aufrunden
                        end
                        local text = string.format("%s %s / %s l (%d%%)",
                            title, formatLiters(level), formatLiters(capacity), percent)
                        if parts ~= nil then
                            table.insert(parts, { text = text, warn = warn })
                        end
                        if out ~= nil then
                            table.insert(out, {
                                text = text,
                                isHeader = false,
                                warn = warn,
                            })
                        end
                    end
                end
            end
        end
    end

    if vehicle.getAttachedImplements ~= nil then
        local implements = vehicle:getAttachedImplements()
        if implements ~= nil then
            for _, implement in ipairs(implements) do
                if implement ~= nil and implement.object ~= nil then
                    collectRigFill(implement.object, out, parts, depth + 1)
                end
            end
        end
    end
end

-- Ladungsgewicht in Tonnen, selbst aus den Fuellstaenden gerechnet
-- (Liter x massPerLiter). Muss sein: auf Dedi-Clients friert
-- getTotalMass auf dem Leergewicht ein.
local function collectLoadMass(vehicle, depth)
    if vehicle == nil or depth > MitspielerHUD.MAX_DEPTH then
        return 0
    end
    local mass = 0

    if vehicle.getFillUnits ~= nil
        and vehicle.getFillUnitCapacity ~= nil
        and vehicle.getFillUnitFillLevel ~= nil then
        local fillUnits = vehicle:getFillUnits()
        if fillUnits ~= nil then
            for i = 1, #fillUnits do
                local capacity = vehicle:getFillUnitCapacity(i) or 0
                local level = vehicle:getFillUnitFillLevel(i) or 0
                if capacity > 0 and level > 0 then
                    local ftIndex = nil
                    if vehicle.getFillUnitFillType ~= nil then
                        ftIndex = vehicle:getFillUnitFillType(i)
                    end
                    if EXCLUDED_FILLTYPES[getFillTypeName(ftIndex)] == nil
                        and ftIndex ~= nil and g_fillTypeManager ~= nil
                        and g_fillTypeManager.getFillTypeByIndex ~= nil then
                        local desc = g_fillTypeManager:getFillTypeByIndex(ftIndex)
                        if desc ~= nil and desc.massPerLiter ~= nil then
                            mass = mass + level * desc.massPerLiter
                        end
                    end
                end
            end
        end
    end

    if vehicle.getAttachedImplements ~= nil then
        local implements = vehicle:getAttachedImplements()
        if implements ~= nil then
            for _, implement in ipairs(implements) do
                if implement ~= nil and implement.object ~= nil then
                    mass = mass + collectLoadMass(implement.object, depth + 1)
                end
            end
        end
    end

    return mass
end

-- ------------------------------------------------------------
-- Tacho-Verankerung
-- ------------------------------------------------------------

-- Sucht das Zifferblatt-Overlay (speedBg, 232x232 Referenzpixel) des
-- Spiel-Tachos. Rueckgabe: Tabelle mit
--   gaugeX/gaugeY  Unterkante links des Zifferblatts (normalisiert)
--   rightX         rechte Kante des gesamten Tacho-HUDs
--   centerX/centerY Zifferblatt-Mitte
--   pxX/pxY        Groesse eines Referenzpixels in Bildschirmeinheiten
--   found          true = echtes Element, false = Schaetzung
function MitspielerHUD:getSpeedoAnchor()
    local sm = nil
    if g_currentMission ~= nil and g_currentMission.hud ~= nil then
        sm = g_currentMission.hud.speedMeter
    end

    if sm ~= nil and sm.vehicle ~= nil and sm.speedBg ~= nil then
        local bg = sm.speedBg
        local x, y, w, h = bg.x, bg.y, bg.width, bg.height
        if x ~= nil and y ~= nil and w ~= nil and w > 0 and h ~= nil and h > 0 then
            local anchor = {
                gaugeX = x,
                gaugeY = y,
                pxX = w / 232,
                pxY = h / 232,
                found = true,
            }
            -- Zifferblatt-Mitte: vom Spiel vorgerechnet (117/116 px),
            -- sonst geometrische Mitte
            if sm.speedGaugeCenterOffsetX ~= nil and sm.speedGaugeCenterOffsetY ~= nil then
                anchor.centerX = x + sm.speedGaugeCenterOffsetX
                anchor.centerY = y + sm.speedGaugeCenterOffsetY
            else
                anchor.centerX = x + w * 0.5
                anchor.centerY = y + h * 0.5
            end
            -- Rechte HUD-Kante: Positions-Anker der SpeedMeterDisplay
            -- (siehe Original-Draw: posX = rechte Kante)
            if sm.getPosition ~= nil then
                local px = sm:getPosition()
                if px ~= nil and px > x then
                    anchor.rightX = px
                end
            end
            if anchor.rightX == nil then
                if g_hudAnchorRight ~= nil then
                    anchor.rightX = g_hudAnchorRight
                else
                    anchor.rightX = x + w + 130 * anchor.pxX
                end
            end
            if not self.anchorLogged then
                self.anchorLogged = true
                print(string.format(
                    "MitspielerHUD: speedBg-Anker x=%.4f y=%.4f w=%.4f h=%.4f rightX=%.4f",
                    x, y, w, h, anchor.rightX))
            end
            return anchor
        end
    end

    -- Fallback: rechts unten anhand des Seitenverhaeltnisses schaetzen
    if not self.anchorLogged then
        self.anchorLogged = true
        print("MitspielerHUD: speedBg nicht verfuegbar, nutze Fallback-Schaetzung")
    end
    local aspect = getAspect()
    local h = 0.30
    local w = h / aspect
    local x = 1 - (0.02 / aspect) - w
    local y = 0.025
    return {
        gaugeX = x,
        gaugeY = y,
        rightX = x + w,
        pxX = w / 232,
        pxY = h / 232,
        centerX = x + w * 0.5,
        centerY = y + h * 0.5,
        found = false,
    }
end

-- Hintergrund der Leiste, dreiteilig mit runden Kappen wie die
-- Fortschrittsbalken des Spiels
function MitspielerHUD:getBarOverlay()
    if self.barOverlay == nil then
        self.barOverlay = false  -- nur ein Erzeugungsversuch
        if ThreePartOverlay ~= nil and ThreePartOverlay.new ~= nil then
            local bar = ThreePartOverlay.new()
            if bar ~= nil and bar.setLeftPart ~= nil and bar.setMiddlePart ~= nil
                and bar.setRightPart ~= nil and bar.setColor ~= nil then
                bar:setLeftPart("gui.progressbar_left", 0, 0)
                bar:setMiddlePart("gui.progressbar_middle", 0, 0)
                bar:setRightPart("gui.progressbar_right", 0, 0)
                bar:setColor(0.012, 0.012, 0.012, 0.85)
                self.barOverlay = bar
            end
        end
    end
    if self.barOverlay == false then
        return nil
    end
    return self.barOverlay
end

-- Hintergrund der oberen Leiste - dieselben Slices wie das Info-HUD
-- des Spiels, damit sich beides nicht beisst
function MitspielerHUD:getTopBarOverlays()
    if self.topBarOverlays == nil then
        self.topBarOverlays = false  -- nur ein Erzeugungsversuch
        if g_overlayManager ~= nil and g_overlayManager.createOverlay ~= nil then
            local r, g, b, a = 0.014, 0.014, 0.014, 0.85
            if HUD ~= nil and HUD.COLOR ~= nil and HUD.COLOR.BACKGROUND ~= nil then
                r, g, b, a = unpack(HUD.COLOR.BACKGROUND)
            end
            -- unbekannter Slice -> nil, kein Fehler
            local left = g_overlayManager:createOverlay("gui.gameInfo_left", 0, 0, 0, 0)
            local middle = g_overlayManager:createOverlay("gui.gameInfo_middle", 0, 0, 0, 0)
            local right = g_overlayManager:createOverlay("gui.gameInfo_right", 0, 0, 0, 0)
            if left ~= nil and middle ~= nil and right ~= nil then
                left:setColor(r, g, b, a)
                middle:setColor(r, g, b, a)
                right:setColor(r, g, b, a)
                self.topBarOverlays = { left = left, middle = middle, right = right }
            end
        end
    end
    if self.topBarOverlays == false then
        return nil
    end
    return self.topBarOverlays
end

-- Gewichts-Symbol fuer die Leiste, gruen wie die uebrigen
-- Tacho-Symbole des Spiels
function MitspielerHUD:getBarIcons()
    if self.barIcons == nil then
        self.barIcons = false  -- nur ein Erzeugungsversuch
        if g_overlayManager ~= nil and g_overlayManager.createOverlay ~= nil then
            local r, g, b, a = 0.62, 0.86, 0.17, 1.0
            if HUD ~= nil and HUD.COLOR ~= nil and HUD.COLOR.ACTIVE ~= nil then
                r, g, b, a = unpack(HUD.COLOR.ACTIVE)
            end
            local weight = g_overlayManager:createOverlay("gui.vehicleOverview_maxWeight", 0, 0, 0, 0)
            if weight ~= nil then
                weight:setColor(r, g, b, a)
                self.barIcons = { weight = weight }
            end
        end
    end
    if self.barIcons == false then
        return nil
    end
    return self.barIcons
end

-- Eigene Piktogramme (Traktor, Anhaenger, Strasse) aus den
-- mitgelieferten DDS-Dateien, gruen wie die Spiel-Symbole
function MitspielerHUD:getVehicleIcons()
    if self.vehicleIcons == nil then
        self.vehicleIcons = false  -- nur ein Erzeugungsversuch
        if Overlay ~= nil and Overlay.new ~= nil then
            local r, g, b, a = 0.62, 0.86, 0.17, 1.0
            if HUD ~= nil and HUD.COLOR ~= nil and HUD.COLOR.ACTIVE ~= nil then
                r, g, b, a = unpack(HUD.COLOR.ACTIVE)
            end
            local tractor = Overlay.new(modDirectory .. "pikto_traktor.dds", 0, 0, 0, 0)
            local trailer = Overlay.new(modDirectory .. "pikto_anhaenger.dds", 0, 0, 0, 0)
            local odo = Overlay.new(modDirectory .. "pikto_odo.dds", 0, 0, 0, 0)
            -- overlayId 0 = Datei nicht geladen
            if tractor ~= nil and trailer ~= nil
                and tractor.overlayId ~= 0 and trailer.overlayId ~= 0 then
                tractor:setColor(r, g, b, a)
                trailer:setColor(r, g, b, a)
                if odo ~= nil and odo.overlayId ~= 0 then
                    odo:setColor(r, g, b, a)
                else
                    odo = nil
                end
                self.vehicleIcons = { tractor = tractor, trailer = trailer, odo = odo }
            end
        end
    end
    if self.vehicleIcons == false then
        return nil
    end
    return self.vehicleIcons
end

-- Dunkle Ersatz-Plakette, falls ThreePartOverlay nicht verfuegbar ist
function MitspielerHUD:getKmPlateOverlay()
    if self.kmPlateOverlay == nil then
        self.kmPlateOverlay = false  -- nur ein Erzeugungsversuch
        if g_overlayManager ~= nil and g_overlayManager.createOverlay ~= nil then
            local ov = g_overlayManager:createOverlay("gui.gearBg", 0, 0, 0, 0)
            if ov ~= nil then
                if ov.setColor ~= nil then
                    ov:setColor(0.014, 0.014, 0.014, 0.85)
                end
                self.kmPlateOverlay = ov
            end
        end
    end
    if self.kmPlateOverlay == false then
        return nil
    end
    return self.kmPlateOverlay
end

-- Hintergrund des Ersatz-Panels, Slices und Farbe wie die
-- Fuellstands-Anzeige des Spiels
function MitspielerHUD:getPanelOverlays()
    if self.panelOverlays == nil then
        self.panelOverlays = false  -- nur ein Erzeugungsversuch
        if g_overlayManager ~= nil and g_overlayManager.createOverlay ~= nil then
            local r, g, b, a = 0.014, 0.014, 0.014, 0.85
            if HUD ~= nil and HUD.COLOR ~= nil and HUD.COLOR.BACKGROUND ~= nil then
                r, g, b, a = unpack(HUD.COLOR.BACKGROUND)
            end
            local left = g_overlayManager:createOverlay("gui.filltypes_left", 0, 0, 0, 0)
            local middle = g_overlayManager:createOverlay("gui.filltypes_middle", 0, 0, 0, 0)
            local right = g_overlayManager:createOverlay("gui.filltypes_right", 0, 0, 0, 0)
            if left ~= nil and middle ~= nil and right ~= nil then
                left:setColor(r, g, b, a)
                middle:setColor(r, g, b, a)
                right:setColor(r, g, b, a)
                self.panelOverlays = { left = left, middle = middle, right = right }
            end
        end
    end
    if self.panelOverlays == false then
        return nil
    end
    return self.panelOverlays
end

-- ------------------------------------------------------------
-- Spritverbrauch von Farm Economy
-- ------------------------------------------------------------

-- Farm Economy rechnet den Verbrauch nach seinen eigenen Einstellungen
-- und zeichnet nichts, solange diese Mod laeuft - dafuer liefert es die
-- fertige Angabe. Zugriff ueber die Mod-Umgebung.
local FARM_ECONOMY = "FS25_FarmEconomy"

-- Liefert (Verbrauchstext, Modustext), z.B. "41 l/h" und "Arbeit",
-- oder nil wenn nichts anzuzeigen ist: Farm Economy nicht geladen,
-- Spritmodul bzw. dessen Anzeige aus, Fahrzeug ohne Diesel.
local function getFarmEconomyUsage(vehicle)
    if vehicle == nil then
        return nil, nil
    end

    local env = nil
    if getfenv ~= nil then
        local global = getfenv(0)
        if type(global) == "table" then
            env = global[FARM_ECONOMY]
        end
    end
    if env == nil then
        env = _G[FARM_ECONOMY]
    end
    if type(env) ~= "table" or type(env.DieselVerbrauch) ~= "table"
        or type(env.DieselVerbrauch.getAnzeige) ~= "function" then
        return nil, nil
    end

    local lph, _, modus, anzeige = env.DieselVerbrauch.getAnzeige(vehicle)
    if lph == nil then
        return nil, nil
    end
    -- Den fertigen Text nehmen (unter 10 l/h mit Nachkommastelle, sonst
    -- stuenden Hoflader dauerhaft auf "0 l/h"). Das "or" faengt aeltere
    -- Farm-Economy-Staende ohne diesen Rueckgabewert ab.
    return anzeige or string.format("%.0f l/h", lph), modus
end

-- Name des Helfers am Steuer, sonst nil. Der Job kennt nur den Index,
-- den Namen hat der HelperManager. Nicht ueber job:getHelperName() -
-- das greift ungeprueft auf helper.title zu, und helper kann nil sein.
--- Wem faehrt dieses Fahrzeug hinterher? Geht die Reihe nach vorne durch, bis
--- ein besetztes Fahrzeug kommt, und liefert dessen Fahrer. Die Funktionen
--- fmFolgtGerade und fmGetZiel haengen am Fahrzeug, wenn die Mod "Folge Mir"
--- geladen ist - ohne sie liefert die Funktion nil und es aendert sich nichts.
local function getFollowName(vehicle)
    if vehicle == nil or vehicle.fmFolgtGerade == nil or not vehicle:fmFolgtGerade() then
        return nil
    end

    local label   = MitspielerHUD.txtFollows or "folgt"
    local aktuell = vehicle
    local tiefe   = 0

    while aktuell ~= nil and tiefe < 20 do
        if aktuell.fmGetZiel == nil then
            break
        end

        local vorne = aktuell:fmGetZiel()

        if vorne == nil then
            break
        end

        local besetzt = vorne.spec_enterable ~= nil
                        and vorne.spec_enterable.isControlled == true

        if besetzt then
            local name = nil

            if vorne.getControllerName ~= nil then
                name = vorne:getControllerName()
            end

            if name ~= nil and name ~= "" then
                return label .. " " .. name
            end

            return label
        end

        if vorne.fmFolgtGerade == nil or not vorne:fmFolgtGerade() then
            break
        end

        aktuell = vorne
        tiefe   = tiefe + 1
    end

    return label
end

local function getHelperName(vehicle)
    local spec = vehicle.spec_aiJobVehicle
    if spec == nil or spec.job == nil then
        return nil
    end

    local name = MitspielerHUD.txtHelper or "Helfer"
    local index = spec.job.helperIndex
    if index ~= nil and g_helperManager ~= nil
        and g_helperManager.getHelperByIndex ~= nil then
        local helper = g_helperManager:getHelperByIndex(index)
        if helper ~= nil and type(helper.title) == "string" and helper.title ~= "" then
            name = name .. " " .. helper.title
        end
    end
    return name
end

-- Fahrzeug, in dem der Spieler gerade sitzt (nil zu Fuss)
local function getOwnVehicle()
    if g_localPlayer ~= nil and g_localPlayer.getCurrentVehicle ~= nil then
        return g_localPlayer:getCurrentVehicle()
    end
    return nil
end

-- ------------------------------------------------------------
-- Datensammlung: 1x pro Sekunde
-- ------------------------------------------------------------

function MitspielerHUD:rebuildLines()
    local lines = {}
    local topEntries = {}
    local ownKm = nil
    local ownLoadText = nil
    local ownMassOwn = nil
    local ownMassRig = nil
    local ownFuelPercent = nil
    local ownFuelLiters = nil
    local myFarmId = getMyFarmId()

    if myFarmId ~= nil and myFarmId ~= 0
        and g_currentMission ~= nil
        and g_currentMission.vehicleSystem ~= nil
        and g_currentMission.vehicleSystem.vehicles ~= nil then

        -- Ersatz-Panel-Zeilen nur aufbauen, wenn die obere Leiste
        -- voraussichtlich NICHT verfuegbar ist (spart die doppelte
        -- Aufbereitung im Normalfall)
        local buildPanel = true
        if g_currentMission.hud ~= nil
            and g_currentMission.hud.gameInfoDisplay ~= nil
            and g_currentMission.hud.gameInfoDisplay.infoBgLeft ~= nil then
            buildPanel = false
        end

        -- Kompakte Ladungsteile eines Gespanns aufbereiten:
        --   Behaelter befuellt -> "Weizen 12.500 / 18.000 l (69%)"
        --   Behaelter leer     -> "Leer 0 / 18.000 l (0%)"
        --   kein Behaelter     -> gar kein Eintrag
        local function buildEntryParts(vehicle)
            local parts = {}
            collectRigFill(vehicle, buildPanel and lines or nil, parts, 1)
            return parts
        end

        -- In die Leiste kommt nur, wer wirklich etwas mit Behaelter
        -- dranhat. Wer mit dem blanken Schlepper oder einem Grubber
        -- unterwegs ist, taucht gar nicht erst auf.
        -- Die Kopfzeile des Ersatz-Panels wird nachtraeglich an der
        -- gemerkten Stelle eingefuegt, damit sie vor den Ladungszeilen
        -- steht, die collectRigFill schreibt.
        local function addEntry(name, vehicle)
            local kopf = #lines + 1
            local parts = buildEntryParts(vehicle)
            if #parts == 0 then
                return
            end
            if buildPanel then
                table.insert(lines, kopf, { text = name, isHeader = true })
            end
            table.insert(topEntries, { name = name, parts = parts })
        end

        -- Alles einsammeln, was fuer den Hof unterwegs ist: Mitspieler,
        -- Helfer und das eigene Fahrzeug. Im Testmodus zusaetzlich die
        -- unbesetzten Hof-Fahrzeuge.
        local mates = {}
        local helpers = {}
        local followers = {}
        local testMates = {}
        local ownVehicle = nil
        for _, vehicle in ipairs(g_currentMission.vehicleSystem.vehicles) do
            if vehicle ~= nil and self.testMode
                and not (vehicle.getIsControlled ~= nil and vehicle:getIsControlled())
                and vehicle.getOwnerFarmId ~= nil
                and vehicle:getOwnerFarmId() == myFarmId
                and vehicle.spec_drivable ~= nil then
                table.insert(testMates, vehicle)
            end
            if vehicle ~= nil and vehicle.getIsControlled ~= nil and vehicle:getIsControlled() then
                if vehicle.getIsEntered ~= nil and vehicle:getIsEntered() then
                    -- Eigenes Fahrzeug: km, Last, Gewicht, Tank
                    ownVehicle = vehicle
                    local spec = vehicle.spec_drivable
                    if spec ~= nil and spec.odometerMilage ~= nil then
                        ownKm = spec.odometerMilage
                    end
                    if vehicle.spec_motorized ~= nil then
                        -- Motorlast (wird laufend vom Server gesynct)
                        local load = vehicle.spec_motorized.smoothedLoadPercentage
                        if load ~= nil then
                            load = math.max(0, math.min(1, load))
                            ownLoadText = string.format("%s %d %%",
                                self.txtLoad or "Last", math.floor(load * 100 + 0.5))
                        end
                    end
                    if vehicle.getTotalMass ~= nil then
                        local massOwn = vehicle:getTotalMass(true)
                        local massAll = vehicle:getTotalMass()
                        -- Auf Clients stehen die Physik-Massen still, da
                        -- muss die Ladung drauf. Auf Server und im
                        -- Einzelspieler steckt sie schon drin.
                        local loadMass = collectLoadMass(vehicle, 1)
                        local isServer = false
                        if g_currentMission.getIsServer ~= nil then
                            isServer = g_currentMission:getIsServer() == true
                        end
                        if massOwn ~= nil then
                            ownMassOwn = massOwn
                            -- Angehaengtes: Leergewicht + Ladung
                            if massAll ~= nil then
                                local rig = massAll - massOwn
                                if not isServer then
                                    rig = rig + loadMass
                                end
                                if rig > 0.05 then
                                    ownMassRig = rig
                                end
                            end
                        end
                    end
                    ownFuelPercent, ownFuelLiters = getFuelPercent(vehicle)
                elseif vehicle.getOwnerFarmId ~= nil
                    and vehicle:getOwnerFarmId() == myFarmId then
                    table.insert(mates, vehicle)
                end
            elseif vehicle ~= nil
                and vehicle.spec_aiJobVehicle ~= nil
                and vehicle.spec_aiJobVehicle.job ~= nil
                and vehicle.getOwnerFarmId ~= nil
                and vehicle:getOwnerFarmId() == myFarmId then
                -- Helfer-Fahrzeug des eigenen Hofs
                table.insert(helpers, vehicle)
            elseif vehicle ~= nil
                and vehicle.fmFolgtGerade ~= nil
                and vehicle:fmFolgtGerade()
                and vehicle.getOwnerFarmId ~= nil
                and vehicle:getOwnerFarmId() == myFarmId then
                -- Faehrt gerade jemandem hinterher (Mod Folge Mir)
                table.insert(followers, vehicle)
            end
        end

        table.sort(mates, function(a, b)
            local nameA = (a.getControllerName ~= nil and a:getControllerName()) or ""
            local nameB = (b.getControllerName ~= nil and b:getControllerName()) or ""
            return nameA < nameB
        end)

        for _, vehicle in ipairs(mates) do
            if #topEntries >= self.MAX_PLAYERS then
                break
            end
            local playerName = "?"
            if vehicle.getControllerName ~= nil then
                playerName = vehicle:getControllerName() or "?"
            end
            addEntry(playerName, vehicle)
        end

        -- Helfer hinter den Mitspielern, ebenfalls alphabetisch. Sie
        -- fuellen nur die Plaetze, die noch frei sind - echte Mitspieler
        -- haben Vorrang, sonst waechst die Leiste bei vielen Helfern
        -- ueber den Bildschirm hinaus.
        table.sort(helpers, function(a, b)
            return (getHelperName(a) or "") < (getHelperName(b) or "")
        end)

        for _, vehicle in ipairs(helpers) do
            if #topEntries >= self.MAX_PLAYERS then
                break
            end
            addEntry(getHelperName(vehicle) or self.txtHelper or "Helfer", vehicle)
        end

        -- Zum Schluss die Fahrzeuge, die jemandem hinterherfahren. So sieht
        -- man auf einen Blick, wessen Reihe gerade wo unterwegs ist.
        table.sort(followers, function(a, b)
            return (getFollowName(a) or "") < (getFollowName(b) or "")
        end)

        for _, vehicle in ipairs(followers) do
            if #topEntries >= self.MAX_PLAYERS then
                break
            end
            addEntry(getFollowName(vehicle) or self.txtFollows or "folgt", vehicle)
        end

        -- Testmodus: eigenes Gespann mit anzeigen (im Normalbetrieb
        -- bewusst ausgeblendet)
        if self.testMode and ownVehicle ~= nil then
            local myName = self.txtMe or "ICH"
            if ownVehicle.getControllerName ~= nil then
                myName = ownVehicle:getControllerName() or myName
            end
            addEntry(myName, ownVehicle)
        end

        -- Testmodus: unbesetzte Hof-Fahrzeuge auffuellen, bis das
        -- Spielerlimit erreicht ist
        if self.testMode then
            for _, vehicle in ipairs(testMates) do
                if #topEntries >= self.MAX_PLAYERS then
                    break
                end
                addEntry("TEST", vehicle)
            end
        end
    end

    self.lines = lines
    self.topEntries = topEntries
    self.topDirty = true  -- Layout-Cache der oberen Leiste erneuern
    self.ownKm = ownKm
    self.ownLoadText = ownLoadText
    self.ownMassOwn = ownMassOwn
    self.ownMassRig = ownMassRig
    self.ownFuelPercent = ownFuelPercent
    self.ownFuelLiters = ownFuelLiters
end

-- ------------------------------------------------------------
-- Mod-Event-Listener
-- ------------------------------------------------------------

-- Konsolenbefehl "mhudTest": Testmodus an/aus (Entwicklerkonsole)
function MitspielerHUD:consoleToggleTest()
    self.testMode = not self.testMode
    self.updateTimer = self.UPDATE_INTERVAL  -- sofort neu einlesen
    if self.testMode then
        return "MitspielerHUD Testmodus AN: unbesetzte Hof-Fahrzeuge werden wie Mitspieler angezeigt"
    end
    return "MitspielerHUD Testmodus AUS"
end

function MitspielerHUD:loadMap()
    print("MitspielerHUD: geladen (Build 57)")

    -- Uebersetzungen einmalig cachen
    self.txtEmpty = getLocText("MHUD_empty", "leer")
    self.txtLoad = getLocText("MHUD_load", "Last")
    self.txtMe = getLocText("MHUD_me", "ICH")
    self.txtHelper = getLocText("MHUD_helper", "Helfer")
    self.txtFollows = getLocText("MHUD_follows", "folgt")

    -- Testbefehl registrieren (nur mit aktivierter Entwicklerkonsole nutzbar)
    if not self.consoleRegistered and addConsoleCommand ~= nil then
        addConsoleCommand("mhudTest",
            "Toggle Coworker HUD test mode", "consoleToggleTest", self)
        self.consoleRegistered = true
    end

    -- Warnton laden
    if self.warnSampleId == nil and createSample ~= nil and loadSample ~= nil then
        local id = createSample("MitspielerHUDWarnton")
        if id ~= nil and id ~= 0 then
            if loadSample(id, modDirectory .. "warnton.wav", false) then
                self.warnSampleId = id
                print("MitspielerHUD: Warnton geladen")
            else
                print("MitspielerHUD: warnton.wav konnte nicht geladen werden")
            end
        end
    end
end

function MitspielerHUD:deleteMap()
    if self.consoleRegistered and removeConsoleCommand ~= nil then
        removeConsoleCommand("mhudTest")
        self.consoleRegistered = false
    end
    self.testMode = false
    self.lines = {}
    self.topEntries = {}
    self.ownKm = nil
    self.ownLoadText = nil
    self.ownMassOwn = nil
    self.ownMassRig = nil
    self.ownFuelPercent = nil
    self.ownFuelLiters = nil
    self.fuelWarnCooldown = 0
end

function MitspielerHUD:update(dt)
    -- Auf dem reinen Dedicated-Server-Prozess gibt es keine Anzeige
    if g_client == nil or g_currentMission == nil then
        return
    end

    self.updateTimer = self.updateTimer + dt
    if self.updateTimer >= self.UPDATE_INTERVAL then
        self.updateTimer = 0
        self:rebuildLines()
    end

    -- Akustische Tank-Warnung: Doppel-Piepton unter 10 %, danach
    -- alle 30 s, bis getankt wurde (kleine Hysterese gegen Flattern).
    -- Gilt NUR fuer das eigene Fahrzeug und ist nur lokal hoerbar.
    if self.fuelWarnCooldown > 0 then
        self.fuelWarnCooldown = self.fuelWarnCooldown - dt
    end
    local fuel = self.ownFuelPercent
    if fuel ~= nil and fuel < self.FUEL_WARN_THRESHOLD then
        if self.fuelWarnCooldown <= 0 then
            self.fuelWarnCooldown = self.FUEL_WARN_REPEAT_MS
            if self.warnSampleId ~= nil and playSample ~= nil then
                playSample(self.warnSampleId, 1, self.FUEL_WARN_VOLUME, 0, 0, 0)
            end
        end
    elseif fuel ~= nil and fuel > self.FUEL_WARN_THRESHOLD + 0.02 then
        self.fuelWarnCooldown = 0  -- nach dem Tanken sofort wieder scharf
    end
end

-- Ist das Spiel-HUD gerade eingeblendet? (Taste "HUD anzeigen/
-- ausblenden"). g_currentMission.hud.isVisible ist das Flag des
-- Spiels; zusaetzlich wird die Sichtbarkeit des Tacho-Overlays
-- geprueft (HUDElement:getVisible -> overlay.visible).
local function isGameHudVisible()
    local hud = g_currentMission ~= nil and g_currentMission.hud or nil
    if hud == nil then
        return true
    end
    if hud.isVisible == false then
        return false
    end
    if hud.getIsVisible ~= nil and hud:getIsVisible() == false then
        return false
    end
    local sm = hud.speedMeter
    if sm ~= nil then
        if sm.speedBg ~= nil and sm.speedBg.visible == false then
            return false
        end
        if sm.getVisible ~= nil and sm:getVisible() == false then
            return false
        end
    end
    return true
end

function MitspielerHUD:draw()
    if g_client == nil or g_currentMission == nil then
        return
    end
    -- Mit ausgeblendetem Spiel-HUD auch nichts eigenes zeichnen
    if not isGameHudVisible() then
        return
    end
    -- Nur aussteigen, wenn es wirklich NICHTS zu zeichnen gibt. Die
    -- Motorlast gehoert ausdruecklich dazu: sie kann als einziger Wert
    -- der unteren Leiste uebrig bleiben.
    if #self.lines == 0 and #self.topEntries == 0
        and self.ownKm == nil and self.ownMassOwn == nil
        and self.ownLoadText == nil and self.ownFuelLiters == nil then
        return
    end
    -- Nicht ueber Menues/Dialoge zeichnen
    if g_gui ~= nil and g_gui.getIsGuiVisible ~= nil and g_gui:getIsGuiVisible() then
        return
    end
    self:renderLines()
end

-- Verbrauch im Zifferblatt, in der Luecke zwischen "KM/H" und der
-- Betriebsstunden-Linie. Betriebsart gruen, Zahl weiss - so wie Farm
-- Economy es ohne diese Mod selbst zeichnet.
function MitspielerHUD:renderDialUsage(anchor)
    -- Nur der Verbrauch: zusammen mit dem Kilometerstand wurde die Zeile
    -- so breit, dass sie links und rechts in die Tacho-Skala lief. Der
    -- Kilometerstand sitzt deshalb in der Leiste unter dem Tacho.
    local usageText, modeText = getFarmEconomyUsage(getOwnVehicle())
    if usageText == nil then
        return
    end

    local size = self.ODO_DIAL_PX * anchor.pxY
    local ty = anchor.centerY + self.ODO_DIAL_Y_PX * anchor.pxY

    local modeLabel = ""
    if modeText ~= nil and modeText ~= "" then
        modeLabel = modeText .. "  "
    end
    local wMode = modeLabel ~= "" and textWidth(size, modeLabel) or 0
    local wUsage = textWidth(size, usageText)
    local x = anchor.centerX - (wMode + wUsage) * 0.5

    -- Betriebsart gruen wie die Symbole des Spiels, Zahl weiss
    setTextAlignment(RenderText.ALIGN_LEFT)
    if wMode > 0 then
        setActiveTextColor()
        renderText(x, ty, size, modeLabel)
        x = x + wMode
    end
    setTextColor(1, 1, 1, 1)
    renderText(x, ty, size, usageText)
end

-- Info-Leiste unter dem Tacho: links Gewicht (Zugmaschine und
-- Angehaengtes), mittig der Kilometerstand, rechts die Motorlast.
-- Der Verbrauch steht im Zifferblatt (siehe renderDialUsage).
function MitspielerHUD:renderBar(anchor)
    -- Platz UNTER dem Tacho haengt von HUD-Skalierung und Sicherheits-
    -- rand des Spielers ab. Reicht er nicht, wird die Leiste zuerst
    -- verkleinert und zur Not UEBER den Tacho gelegt - frueher fiel
    -- sie in dem Fall stillschweigend weg (Mitspieler sah sie nie).
    local barH = self.BAR_H_PX * anchor.pxY
    local gap = self.BAR_GAP_PX * anchor.pxY
    local space = anchor.gaugeY - self.BAR_MIN_Y
    local barY, modus

    if space >= barH + gap then
        barY = anchor.gaugeY - barH - gap
        modus = "unten"
    elseif space - gap >= barH * self.BAR_MIN_SCALE then
        barH = space - gap
        barY = self.BAR_MIN_Y
        modus = "unten (verkleinert)"
    else
        -- Kein Platz unten: ueber den Tacho bzw. ueber die
        -- Fuellstands-Anzeige des Spiels legen
        barY = anchor.gaugeY + 232 * anchor.pxY + gap
        local fld = nil
        if g_currentMission ~= nil and g_currentMission.hud ~= nil then
            fld = g_currentMission.hud.fillLevelsDisplay
        end
        if fld ~= nil and fld.vehicle ~= nil and fld.bgLeft ~= nil
            and fld.bgLeft.y ~= nil and fld.bgLeft.height ~= nil
            and fld.fillLevelData ~= nil and #fld.fillLevelData > 0 then
            local top = fld.bgLeft.y + fld.bgLeft.height + gap
            if top > barY then
                barY = top
            end
        end
        modus = "oben"
    end

    if not self.barLayoutLogged then
        self.barLayoutLogged = true
        print(string.format(
            "MitspielerHUD: Leiste %s (gaugeY=%.4f Platz=%.4f Hoehe=%.4f)",
            modus, anchor.gaugeY, space, barH))
    end

    local size = math.min(self.BAR_TEXT_PX * anchor.pxY, barH * 0.62)
    local pad = self.BAR_PAD_PX * anchor.pxX
    local ty = barY + barH * 0.5 - size * 0.36

    local icons = self:getBarIcons()
    local vicons = self:getVehicleIcons()
    local iconW = 15 * anchor.pxX
    local iconH = 15 * anchor.pxY
    local iconY = barY + (barH - iconH) * 0.5
    local iconGap = 5 * anchor.pxX
    local minGap = 14 * anchor.pxX
    local iconSpace = iconW + iconGap

    -- Breitenbedarf: reicht die HUD-Breite nicht, waechst die Leiste
    -- nach LINKS ueber den Tacho hinaus (nie ueberlappen)
    local massText, rigText
    local wLeft = 0
    if self.ownMassOwn ~= nil then
        massText = string.format("%.1f t", self.ownMassOwn)
        wLeft = (vicons ~= nil and iconSpace or 0) + textWidth(size, massText)
        if self.ownMassRig ~= nil then
            rigText = string.format("%.1f t)", self.ownMassRig)
            wLeft = wLeft + textWidth(size, "  (")
                + (vicons ~= nil and iconSpace or 0) + textWidth(size, rigText)
        end
    end

    -- Mitte: Strassen-Piktogramm (ersatzweise "ODO") + Kilometerstand
    local odoIcon = vicons ~= nil and vicons.odo or nil
    local kmText, kmLabel = nil, ""
    local wMid, wKmLabel = 0, 0
    if self.ownKm ~= nil then
        kmText = string.format("%.1f km", self.ownKm)
        if odoIcon == nil then
            kmLabel = "ODO "
            wKmLabel = textWidth(size, kmLabel)
        end
        wMid = (odoIcon ~= nil and iconSpace or 0) + wKmLabel
            + textWidth(size, kmText)
    end

    local wRight = 0
    if self.ownLoadText ~= nil then
        wRight = textWidth(size, self.ownLoadText)
    end

    local needed = 2 * pad + wLeft + wMid + wRight
    local bloecke = 0
    for _, w in ipairs({ wLeft, wMid, wRight }) do
        if w > 0 then
            bloecke = bloecke + 1
        end
    end
    if bloecke > 1 then
        needed = needed + minGap * 2 * (bloecke - 1)
    end

    local barW = anchor.rightX - anchor.gaugeX
    if needed > barW then
        barW = needed
    end
    local barX = anchor.rightX - barW

    -- Hintergrund
    local capW = self.BAR_CAP_PX * anchor.pxX
    local bar = self:getBarOverlay()
    if bar ~= nil then
        bar:setLeftPart(nil, capW, barH)
        bar:setMiddlePart(nil, math.max(0, barW - 2 * capW), barH)
        bar:setRightPart(nil, capW, barH)
        bar:setPosition(barX, barY)
        bar:render()
    else
        local plate = self:getKmPlateOverlay()
        if plate ~= nil then
            plate:setDimension(barW, barH)
            plate:setPosition(barX, barY)
            plate:render()
        end
    end

    local cursor = 0
    local function drawText(text)
        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextColor(1, 1, 1, 1)
        renderText(cursor, ty, size, text)
        cursor = cursor + textWidth(size, text)
    end
    local function drawIcon(ov)
        ov:setDimension(iconW, iconH)
        ov:setPosition(cursor, iconY)
        ov:render()
        cursor = cursor + iconW + iconGap
    end

    -- Links: Traktor-Piktogramm + Gewicht, in Klammern das
    -- Angehaengte inkl. Ladung
    local leftEnd = nil
    if massText ~= nil then
        cursor = barX + pad
        if vicons ~= nil then
            drawIcon(vicons.tractor)
        elseif icons ~= nil then
            drawIcon(icons.weight)
        end
        if rigText ~= nil then
            drawText(massText .. "  (")
            if vicons ~= nil then
                drawIcon(vicons.trailer)
            end
            drawText(rigText)
        else
            drawText(massText)
        end
        leftEnd = cursor
    end

    -- Mitte: Strasse plus Kilometerstand, zentriert im freien Raum
    -- zwischen den Nachbarn. Starr in der Leistenmitte kaeme er dem
    -- breiten Gewichtsblock zu nah.
    local rightStartX = barX + barW - pad - wRight
    local midStart, midEnd = nil, nil
    if kmText ~= nil then
        local freiVon = leftEnd or (barX + pad)
        local freiBis = wRight > 0 and rightStartX or (barX + barW - pad)
        cursor = freiVon + (freiBis - freiVon - wMid) * 0.5
        midStart = cursor
        if odoIcon ~= nil then
            drawIcon(odoIcon)
        elseif wKmLabel > 0 then
            setActiveTextColor()
            renderText(cursor, ty, size, kmLabel)
            cursor = cursor + wKmLabel
        end
        drawText(kmText)
        midEnd = cursor
    end

    -- Rechts: Motorlast. Der Spritverbrauch steht bewusst NICHT hier -
    -- den zeigt die Zeile im Zifferblatt.
    local rightStart = nil
    if wRight > 0 and self.ownLoadText ~= nil then
        cursor = rightStartX
        rightStart = cursor
        drawText(self.ownLoadText)
    end

    -- Duenne Trennstriche mittig zwischen den Bloecken
    local function trennstrich(ende, start)
        if drawLine2D == nil or ende == nil or start == nil then
            return
        end
        local sepH = 12 * anchor.pxY
        local sy = barY + (barH - sepH) * 0.5
        local sx = (ende + start) * 0.5
        drawLine2D(sx, sy, sx, sy + sepH, 2 * anchor.pxX, 1, 1, 1, 0.25)
    end
    trennstrich(leftEnd, midStart or rightStart)
    trennstrich(midEnd, rightStart)
end

-- Mitspieler-Panel: eigenes Panel im HUD-Look DIREKT UEBER der
-- Fuellstands-Anzeige des Spiels ("Siliermittel"-Panel). Ist diese
-- gerade ausgeblendet, sitzt das Panel an ihrer Stelle ueber dem
-- Tacho-HUD.
function MitspielerHUD:renderMatesPanel(anchor)
    -- Anker suchen: Oberkante + linke Kante der FillLevels-Anzeige
    local baseX = nil
    local baseY = nil
    local minW = 0
    local fld = nil
    if g_currentMission ~= nil and g_currentMission.hud ~= nil then
        fld = g_currentMission.hud.fillLevelsDisplay
    end
    if fld ~= nil and fld.vehicle ~= nil
        and fld.fillLevelData ~= nil and #fld.fillLevelData > 0
        and fld.bgLeft ~= nil and fld.bgLeft.x ~= nil
        and fld.bgLeft.height ~= nil and fld.bgLeft.height > 0 then
        baseX = fld.bgLeft.x
        baseY = fld.bgLeft.y + fld.bgLeft.height
        local w = (fld.bgLeft.width or 0) + (fld.bgScale ~= nil and fld.bgScale.width or 0)
            + (fld.bgRight ~= nil and fld.bgRight.width or 0)
        if w > 0 then
            minW = w
        end
    else
        -- FillLevels-Anzeige nicht sichtbar: an deren Stelle ueber
        -- dem Tacho (Zifferblatt-Oberkante + Abstand)
        baseX = anchor.gaugeX
        baseY = anchor.gaugeY + 232 * anchor.pxY + 10 * anchor.pxY
    end

    local headSize = self.PANEL_HEAD_PX * anchor.pxY
    local subSize  = self.PANEL_SUB_PX * anchor.pxY
    local padX     = self.PANEL_PAD_X_PX * anchor.pxX
    local padY     = self.PANEL_PAD_Y_PX * anchor.pxY
    local indent   = self.PANEL_INDENT_PX * anchor.pxX

    -- Panelgroesse aus den Zeilen berechnen
    local maxTextW = 0
    local totalH = 0
    for i = 1, #self.lines do
        local line = self.lines[i]
        local size = line.isHeader and headSize or subSize
        local w = textWidth(size, line.text)
        if not line.isHeader then
            w = w + indent
        end
        if w > maxTextW then
            maxTextW = w
        end
        totalH = totalH + size * 1.45
        if line.isHeader and i > 1 then
            totalH = totalH + self.PANEL_BLOCK_PX * anchor.pxY
        end
    end

    local panelW = math.max(maxTextW + 2 * padX, minW)
    local panelH = totalH + 2 * padY
    local panelX = baseX
    local panelY = baseY + self.PANEL_GAP_PX * anchor.pxY

    -- Hintergrund (drei Teile, wie das Original-Panel)
    local ov = self:getPanelOverlays()
    if ov ~= nil then
        local capW = self.PANEL_CAP_PX * anchor.pxX
        if 2 * capW > panelW then
            capW = panelW * 0.5
        end
        ov.left:setDimension(capW, panelH)
        ov.left:setPosition(panelX, panelY)
        ov.middle:setDimension(panelW - 2 * capW, panelH)
        ov.middle:setPosition(panelX + capW, panelY)
        ov.right:setDimension(capW, panelH)
        ov.right:setPosition(panelX + panelW - capW, panelY)
        ov.left:render()
        ov.middle:render()
        ov.right:render()
    end

    -- Zeilen von oben nach unten
    setTextAlignment(RenderText.ALIGN_LEFT)
    local cursor = panelY + panelH - padY
    for i = 1, #self.lines do
        local line = self.lines[i]
        local size = line.isHeader and headSize or subSize
        if line.isHeader and i > 1 then
            cursor = cursor - self.PANEL_BLOCK_PX * anchor.pxY
        end
        cursor = cursor - size * 1.45
        local tx = panelX + padX
        if not line.isHeader then
            tx = tx + indent
        end

        if line.isHeader then
            setTextColor(0.62, 0.86, 0.17, 1.0)  -- FS-Gruen
        elseif line.warn then
            setTextColor(1, 0.25, 0.25, 1)       -- fast voll -> rot
        else
            setTextColor(1, 1, 1, 1)
        end
        renderText(tx, cursor, size, line.text)
    end
end

-- Obere Leiste: links neben dem Spiel-Info-HUD (Uhrzeit/Geld),
-- gleicher Look, pro Mitspieler "Name: Ladung", getrennt durch
-- senkrechte Trennstriche. Rueckgabe true, wenn gezeichnet wurde.
function MitspielerHUD:renderMatesTopBar()
    local gid = nil
    if g_currentMission ~= nil and g_currentMission.hud ~= nil then
        gid = g_currentMission.hud.gameInfoDisplay
    end
    if gid == nil or gid.infoBgLeft == nil then
        return false
    end
    local bg = gid.infoBgLeft
    if bg.x == nil or bg.y == nil
        or bg.width == nil or bg.width <= 0
        or bg.height == nil or bg.height <= 0 then
        return false
    end

    -- Referenzpixel des Info-HUDs: Hoehe 65 px, linke Kappe 10 px
    -- (siehe GameInfoDisplay:storeScaledValues)
    local pxY = bg.height / 65
    local pxX = bg.width / 10

    local size    = 17 * pxY   -- gleiche Textgroesse wie Uhrzeit/Geld
    local capW    = 10 * pxX
    local padX    = 12 * pxX
    local sepPad  = 12 * pxX
    local sepW    = 2 * pxX
    local gap     = 4 * pxX

    -- Layout-Cache: Texte und Breiten nur neu berechnen, wenn sich
    -- die Daten (1x/s) oder die HUD-Groesse geaendert haben - nicht
    -- in jedem Frame (spart pro Frame Dutzende Engine-Aufrufe)
    local layout = self.topLayout
    if layout == nil or self.topDirty or layout.size ~= size then
        layout = { size = size, entries = {}, contentW = 0 }
        for i = 1, #self.topEntries do
            local e = self.topEntries[i]
            local le = { nameText = e.name .. ": ", segs = {} }
            le.nameW = textWidth(size, le.nameText)
            local w = le.nameW
            for p = 1, #e.parts do
                local seg = e.parts[p].text
                if p < #e.parts then
                    seg = seg .. ", "
                end
                local segW = textWidth(size, seg)
                table.insert(le.segs, { text = seg, w = segW, warn = e.parts[p].warn })
                w = w + segW
            end
            table.insert(layout.entries, le)
            layout.contentW = layout.contentW + w
            if i > 1 then
                layout.contentW = layout.contentW + sepPad + sepW + sepPad
            end
        end
        self.topLayout = layout
        self.topDirty = false
    end
    local entries = layout.entries
    local contentW = layout.contentW

    local barW = contentW + 2 * padX
    local barH = bg.height
    local barX = bg.x - gap - barW
    local barY = bg.y
    if barX < 0 then
        barX = 0  -- Notbremse bei extrem vielen/langen Eintraegen
    end

    -- Hintergrund im Info-HUD-Look (einmalig erzeugt -
    -- draw() ist als Ganzes abgesichert)
    local ov = self:getTopBarOverlays()
    if ov ~= nil then
        ov.left:setDimension(capW, barH)
        ov.left:setPosition(barX, barY)
        ov.middle:setDimension(math.max(0, barW - 2 * capW), barH)
        ov.middle:setPosition(barX + capW, barY)
        ov.right:setDimension(capW, barH)
        ov.right:setPosition(barX + barW - capW, barY)
        ov.left:render()
        ov.middle:render()
        ov.right:render()
    end

    -- Eintraege zeichnen (Baseline wie die Spiel-Texte: +27 px)
    local ty = barY + 27 * pxY
    local cursor = barX + padX
    setTextAlignment(RenderText.ALIGN_LEFT)
    for i = 1, #entries do
        local e = entries[i]

        if i > 1 then
            -- Trennstrich (wie die Original-Trenner: 2 px breit, 35 px
            -- hoch, 17 px ueber der Unterkante)
            cursor = cursor + sepPad
            local sepX = cursor + sepW * 0.5
            local sepY1 = barY + 17 * pxY
            local sepY2 = sepY1 + 35 * pxY
            if drawLine2D ~= nil then
                drawLine2D(sepX, sepY1, sepX, sepY2, sepW, 1, 1, 1, 0.3)
            else
                setTextColor(1, 1, 1, 0.3)
                renderText(cursor, ty, size, "|")
            end
            cursor = cursor + sepW + sepPad
        end

        setTextColor(0.62, 0.86, 0.17, 1.0)  -- Name in FS-Gruen
        renderText(cursor, ty, size, e.nameText)
        cursor = cursor + e.nameW

        for p = 1, #e.segs do
            local seg = e.segs[p]
            if seg.warn then
                setTextColor(1, 0.25, 0.25, 1)  -- Warnung -> rot
            else
                setTextColor(1, 1, 1, 1)
            end
            renderText(cursor, ty, size, seg.text)
            cursor = cursor + seg.w
        end
    end

    return true
end

-- Aktuelle Liter UEBER dem Tank-Balken des Spiel-Tachos, in der Luecke
-- zwischen Balken-Oberkante und Tank-Symbol. Anker ist das Tank-Symbol
-- selbst (sm.fuelIcon wird vom Spiel jeden Frame positioniert); fehlt
-- es, wird die Balkenposition aus den Original-Offsets berechnet.
function MitspielerHUD:renderFuelLiters(anchor)
    local sm = nil
    if g_currentMission ~= nil and g_currentMission.hud ~= nil then
        sm = g_currentMission.hud.speedMeter
    end
    if sm == nil then
        return
    end

    local size = self.FUEL_TEXT_PX * anchor.pxY
    local x, ty

    local gap = self.FUEL_GAP_PX * anchor.pxY
    local icon = sm.fuelIcon
    if icon ~= nil and icon.x ~= nil and icon.y ~= nil and icon.width ~= nil then
        x = icon.x + icon.width * 0.5
        -- mittig in die Luecke: gleich viel Luft zu Symbol und Balken
        ty = icon.y - (gap + size) * 0.5
    else
        -- Notweg: Balkenfuss aus den Referenz-Offsets, Balkenlaenge 130 px
        x = anchor.rightX + (sm.sectionOffsetX or (9 * anchor.pxX))
            + (sm.fuelOffsetX or (-30 * anchor.pxX)) + (sm.fuelBarOffsetX or 0)
        local barBottom = anchor.gaugeY + (sm.sectionOffsetY or (47 * anchor.pxY))
            + (sm.fuelOffsetY or 0) + (sm.fuelBarOffsetY or 0)
        ty = barBottom + 130 * anchor.pxY + (gap - size) * 0.5
    end
    ty = ty + self.FUEL_TEXT_SHIFT_PX * anchor.pxY
    x = x + self.FUEL_TEXT_OFFSET_X_PX * anchor.pxX

    local text = string.format("%d l", math.floor(self.ownFuelLiters + 0.5))
    setTextAlignment(RenderText.ALIGN_CENTER)
    if self.ownFuelPercent ~= nil and self.ownFuelPercent < self.FUEL_WARN_THRESHOLD then
        setTextColor(1, 0.25, 0.25, 1)   -- fast leer -> rot
    else
        setTextColor(1, 1, 1, 1)
    end
    renderText(x, ty, size, text)
end

function MitspielerHUD:renderLines()
    local anchor = self:getSpeedoAnchor()

    setTextBold(false)

    -- Nur zeichnen, wenn der echte Tacho gefunden wurde - sonst
    -- wuerden die Werte frei im Bild haengen
    if anchor.found then
        -- Verbrauch im Zifferblatt (prueft selbst, ob Farm Economy
        -- gerade etwas liefert - der Wert kommt pro Bild frisch)
        self:renderDialUsage(anchor)
        -- Leiste unter dem Tacho: Gewicht, Kilometerstand, Motorlast
        if self.ownMassOwn ~= nil or self.ownKm ~= nil
            or self.ownLoadText ~= nil then
            self:renderBar(anchor)
        end
    end

    -- Liter ueber dem Tank-Balken des Spiel-Tachos
    if self.ownFuelLiters ~= nil and anchor.found then
        self:renderFuelLiters(anchor)
    end

    -- Mitspieler: obere Leiste neben Uhrzeit/Geld; klappt das nicht,
    -- ersatzweise das Panel ueber der Fuellstands-Anzeige
    if #self.topEntries > 0 then
        if not self:renderMatesTopBar() and #self.lines > 0 then
            self:renderMatesPanel(anchor)
        end
    end

    -- Render-Zustand zuruecksetzen, sonst leidet fremdes UI
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
    setTextBold(false)
end

addModEventListener(MitspielerHUD)
