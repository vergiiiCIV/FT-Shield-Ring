-- FT - Shield Ring : anneau de Mot de pouvoir : Bouclier autour du cercle de vie d'AishCore.
-- Anneau intérieur = absorption restante (se vide dans le sens horaire).
-- Arc extérieur = Âme affaiblie (temps restant). Nombre = points d'absorption restants.
-- Les valeurs « secrètes » du client sont données telles quelles aux barres et au texte
-- (jamais comparées), le jeu les affiche lui-même.

local _, playerClass = UnitClass("player")
if playerClass ~= "PRIEST" then
    return
end

local ADDON = ...
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

-- Mot de pouvoir : Bouclier, absorption de base par rang (sort -> points).
local PWS_BASE = {
    [17] = 48, [592] = 92, [600] = 162, [3747] = 233, [6065] = 303,
    [6066] = 381, [10898] = 499, [10899] = 608, [10900] = 769, [10901] = 950,
}
local PWS_COEF = 0.1 -- part des soins bonus ajoutée au bouclier
local PWS_DURATION = 30
local WS_SPELL, WS_DURATION = 6788, 15
local WS_COLOR = { 190 / 255, 89 / 255, 68 / 255 }

local PRESETS = {
    sacre = { 1.00, 0.91, 0.43 },
    ombre = { 0.66, 0.44, 1.00 },
    givre = { 0.42, 0.78, 1.00 },
    naaru = { 0.96, 0.97, 1.00 },
}

local DEFAULTS = {
    x = 0, y = 0,          -- décalage par rapport au cercle de vie
    gap = 10,              -- écart entre le cercle de vie et l'anneau
    dotSize = 7,
    dots = 64,
    color = "sacre",
    showText = true,
    showTime = true,       -- temps restant du bouclier (en face du nombre)
    showWS = true,
    locked = true,
    combatOnly = true,     -- caché hors combat
}

local db
local state = { active = false, max = 1, castAt = nil, wsUntil = nil, test = false, untilT = nil }

local function isSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

local function color()
    if db.color == "classe" then
        local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS.PRIEST
        if c then
            return c.r, c.g, c.b
        end
    end
    local c = PRESETS[db.color] or PRESETS.sacre
    return c[1], c[2], c[3]
end

---------------------------------------------------------------------------
-- Cadres
---------------------------------------------------------------------------

local root = CreateFrame("Frame", "VergiShieldRingFrame", UIParent)
root:SetFrameStrata("MEDIUM")
root:SetSize(10, 10)
root:SetMovable(true)
root:SetClampedToScreen(true)
root:Hide()

local dragBox = root:CreateTexture(nil, "BACKGROUND")
dragBox:SetAllPoints()
dragBox:SetColorTexture(0.2, 0.6, 1, 0.15)
dragBox:Hide()

local segs, bgs, wsDots = {}, {}, {}

local text = root:CreateFontString(nil, "OVERLAY", "GameFontNormal")
text:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")

local timeText = root:CreateFontString(nil, "OVERLAY", "GameFontNormal")
timeText:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
timeText:Hide()

-- Le cercle d'AishCore n'est utilisé que lorsqu'il est visible (hors combat il est caché
-- et déplacé) : sa position et sa taille sont alors mémorisées pour la suite.
local function anchorFrame()
    local a = rawget(_G, "AishCoreHealthRing")
    if a and a.IsVisible and a:IsVisible() and a:GetCenter() then
        return a
    end
    return nil
end

local function remember()
    local a = anchorFrame()
    if not a then
        return false
    end
    local k = a:GetEffectiveScale() / root:GetEffectiveScale()
    local ax, ay = a:GetCenter()
    local ux, uy = UIParent:GetCenter()
    db.ax, db.ay = ax * k - ux, ay * k - uy
    db.ar = a:GetWidth() * k / 2
    return true
end

local function radius()
    return (db.ar or 60) + db.gap
end

-- Plages des segments : le segment i est plein quand l'absorption atteint son seuil.
local function setRanges()
    local n, max = #segs, math.max(1, state.max)
    local step = max / n
    for i = 1, n do
        local high = step * i
        segs[i]:SetMinMaxValues(high - step * 0.2, high)
    end
end

local function buildDots()
    local n = db.dots
    local r = radius()
    local size = db.dotSize
    local cr, cg, cb = color()
    for i = 1, math.max(n, #segs) do
        local s, b = segs[i], bgs[i]
        if i <= n then
            if not s then
                b = root:CreateTexture(nil, "ARTWORK")
                b:SetTexture(MEDIA .. "Dot")
                s = CreateFrame("StatusBar", nil, root)
                s:SetStatusBarTexture(MEDIA .. "Dot")
                s:SetOrientation("HORIZONTAL")
                segs[i], bgs[i] = s, b
            end
            -- Haut du cercle puis sens horaire.
            local ang = math.rad(90 - (i - 0.5) * 360 / n)
            local x, y = math.cos(ang) * r, math.sin(ang) * r
            for _, w in ipairs({ s, b }) do
                w:ClearAllPoints()
                w:SetSize(size, size)
                w:SetPoint("CENTER", root, "CENTER", x, y)
                w:Show()
            end
            b:SetVertexColor(0.12, 0.12, 0.12, 0.85)
            s:SetStatusBarColor(cr, cg, cb, 1)
        elseif s then
            s:Hide()
            b:Hide()
        end
    end
    for i = #segs, n + 1, -1 do
        segs[i], bgs[i] = nil, nil
    end
    -- Âme affaiblie : arc extérieur, plus fin.
    local m = 48
    local wr = r + size + 2
    for i = 1, m do
        local d = wsDots[i]
        if not d then
            d = root:CreateTexture(nil, "ARTWORK")
            d:SetTexture(MEDIA .. "Dot")
            wsDots[i] = d
        end
        local ang = math.rad(90 - (i - 0.5) * 360 / m)
        d:ClearAllPoints()
        d:SetSize(math.max(3, size - 3), math.max(3, size - 3))
        d:SetPoint("CENTER", root, "CENTER", math.cos(ang) * wr, math.sin(ang) * wr)
        d:SetVertexColor(WS_COLOR[1], WS_COLOR[2], WS_COLOR[3], 1)
        d:Hide()
    end
    text:ClearAllPoints()
    text:SetPoint("BOTTOMLEFT", root, "CENTER", r * 0.75, r * 0.75)
    text:SetTextColor(cr, cg, cb)
    timeText:ClearAllPoints()
    timeText:SetPoint("BOTTOMRIGHT", root, "CENTER", -r * 0.75, r * 0.75)
    timeText:SetTextColor(cr, cg, cb)
    root:SetSize(2 * (wr + size), 2 * (wr + size))
    setRanges()
end

local function layout()
    remember()
    root:ClearAllPoints()
    if db.ax then
        root:SetPoint("CENTER", UIParent, "CENTER", db.ax + db.x, db.ay + db.y)
    else
        root:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y - 140)
    end
    local a = rawget(_G, "AishCoreHealthRing")
    if a and a.GetFrameLevel then
        root:SetFrameLevel(math.min(10000, a:GetFrameLevel() + 10))
    end
    buildDots()
end

---------------------------------------------------------------------------
-- Bouclier
---------------------------------------------------------------------------

local function shieldAura()
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if not get then
        return nil
    end
    for id in pairs(PWS_BASE) do
        local ok, aura = pcall(get, id)
        if ok and aura then
            return aura, id
        end
    end
    return nil
end

-- Taille prévue du bouclier quand le jeu ne donne pas la valeur lisible.
local function predictedMax(spellID)
    local base = PWS_BASE[spellID]
    if not base then
        for id, v in pairs(PWS_BASE) do
            if IsSpellKnown and IsSpellKnown(id) and v > (base or 0) then
                base = v
            end
        end
    end
    local bonus = GetSpellBonusHealing and GetSpellBonusHealing() or 0
    if isSecret(bonus) or type(bonus) ~= "number" then
        bonus = 0
    end
    return (base or 950) + bonus * PWS_COEF
end

local function readAbsorb()
    if state.test then
        return state.max * 0.65
    end
    if not UnitGetTotalAbsorbs then
        return nil
    end
    local ok, amount = pcall(UnitGetTotalAbsorbs, "player")
    if not ok then
        return nil
    end
    return amount
end

-- Lit le vrai debuff Âme affaiblie sur toi.
-- Renvoie : secondes restantes, "present" (durée illisible), "absent", ou nil (illisible, ex. en combat).
local function readWS()
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if not get then
        return nil
    end
    local ok, aura = pcall(get, WS_SPELL)
    if not ok or isSecret(aura) then
        return nil
    end
    if aura == nil then
        -- En combat, les auras peuvent être cachées : « pas d'aura » n'est pas fiable.
        if InCombatLockdown() then
            return nil
        end
        return "absent"
    end
    local exp = aura.expirationTime
    if exp ~= nil and not isSecret(exp) and type(exp) == "number" and exp > 0 then
        return exp - GetTime()
    end
    return "present"
end

local function updateWS()
    local remain = 0
    if state.test then
        remain = WS_DURATION * 0.5
    else
        local r = readWS()
        if r == "absent" then
            state.wsUntil = nil
        elseif type(r) == "number" then
            remain = r
            state.wsUntil = GetTime() + r
        elseif r == "present" then
            remain = state.wsUntil and (state.wsUntil - GetTime()) or WS_DURATION
            if remain <= 0 then
                remain = 0.5
            end
        elseif state.wsUntil then
            remain = state.wsUntil - GetTime()
            if remain <= 0 then
                state.wsUntil = nil
            end
        end
    end
    local m = #wsDots
    local lit = (db.showWS and remain > 0) and math.ceil(math.min(1, remain / WS_DURATION) * m) or 0
    for i = 1, m do
        wsDots[i]:SetShown(i <= lit)
    end
    return remain > 0
end

local stopShieldLater = false
local function update()
    if not state.active then
        return
    end
    local amount = readAbsorb()
    if amount == nil then
        return
    end
    if not isSecret(amount) and type(amount) == "number" then
        if amount <= 0 then
            stopShieldLater = true
        end
        if amount > state.max then
            state.max = amount
            setRanges()
        end
    end
    for i = 1, #segs do
        pcall(segs[i].SetValue, segs[i], amount)
    end
    if db.showText then
        pcall(text.SetFormattedText, text, "%d", amount)
        text:Show()
    else
        text:Hide()
    end
end

local function startShield(spellID)
    local amount = readAbsorb()
    if amount ~= nil and not isSecret(amount) and type(amount) == "number" and amount > 0 then
        state.max = amount
    else
        state.max = predictedMax(spellID)
    end
    state.active = true
    state.untilT = GetTime() + PWS_DURATION
    if not state.wsUntil or state.wsUntil < GetTime() then
        state.wsUntil = GetTime() + WS_DURATION
    end
    setRanges()
    root:Show()
    update()
end

local function stopShield()
    state.active = false
    for i = 1, #segs do
        segs[i]:SetValue(0)
    end
    text:Hide()
    timeText:Hide()
    if not updateWS() and db.locked and not state.test then
        root:Hide()
    end
end

-- Bouclier présent ? Hors combat : le buff. En combat (buffs cachés) : l'absorption.
local function absorbState()
    local amount = readAbsorb()
    if amount == nil then
        return nil
    end
    if isSecret(amount) or type(amount) ~= "number" then
        return "secret"
    end
    return amount > 0
end

local function refresh()
    if state.test then
        return
    end
    local has
    local abs = absorbState()
    if abs == true or abs == false then
        has = abs
    elseif not InCombatLockdown() then
        has = shieldAura() ~= nil
    else
        has = "secret"
    end
    if has == "secret" then
        if not state.active then
            startShield(nil)
        else
            update()
        end
    elseif has and not state.active then
        local _, id = shieldAura()
        startShield(id)
    elseif not has and state.active then
        stopShield()
    elseif state.active then
        update()
        if stopShieldLater then
            stopShieldLater = false
            stopShield()
        end
    end
    if not state.active and not updateWS() and db.locked then
        root:Hide()
    end
end

-- « Combat uniquement » : l'anneau reste invisible hors combat (sauf aperçu ou déplacement).
local function applyAlpha()
    local show = state.test or not db.locked or not db.combatOnly or InCombatLockdown()
    root:SetAlpha(show and 1 or 0)
end

-- Temps restant du bouclier : durée exacte du jeu hors combat si lisible, sinon 30 s
-- comptées depuis l'apparition du bouclier.
local function updateTime()
    if not (db.showTime and (state.active or state.test)) then
        timeText:Hide()
        return
    end
    local remain
    if state.test then
        remain = 18
    else
        if not InCombatLockdown() then
            local aura = shieldAura()
            local exp = aura and aura.expirationTime
            if exp and not isSecret(exp) and exp > 0 then
                remain = exp - GetTime()
                state.untilT = exp
            end
        end
        remain = remain or (state.untilT and state.untilT - GetTime())
    end
    if remain and remain > 0 then
        timeText:SetFormattedText("%d s", math.ceil(remain))
        timeText:Show()
    else
        timeText:Hide()
    end
end

-- Âme affaiblie et fin du bouclier : petit rafraîchissement régulier tant que visible.
local acc = 0
root:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.1 then
        return
    end
    acc = 0
    applyAlpha()
    updateTime()
    local ws = updateWS()
    if state.active and not state.test and state.untilT and GetTime() > state.untilT then
        stopShield()
    end
    if not state.active and not ws and db.locked and not state.test then
        root:Hide()
    end
end)

---------------------------------------------------------------------------
-- Déplacement
---------------------------------------------------------------------------

root:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" and not db.locked then
        self:StartMoving()
    end
end)
root:SetScript("OnMouseUp", function(self)
    if db.locked then
        return
    end
    self:StopMovingOrSizing()
    local fx, fy = self:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if db.ax then
        db.x, db.y = math.floor(fx - ux - db.ax + 0.5), math.floor(fy - uy - db.ay + 0.5)
    else
        db.x, db.y = math.floor(fx - ux + 0.5), math.floor(fy - uy + 140 + 0.5)
    end
    layout()
end)

local function setLocked(locked)
    db.locked = locked
    if db.combatOnly ~= nil then
        root:SetAlpha((state.test or not locked or not db.combatOnly or InCombatLockdown()) and 1 or 0)
    end
    root:EnableMouse(not locked)
    dragBox:SetShown(not locked)
    if not locked then
        root:Show()
    elseif not state.active and not state.test then
        root:Hide()
    end
end

---------------------------------------------------------------------------
-- Événements
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player")
ev:RegisterUnitEvent("UNIT_AURA", "player")
ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
ev:SetScript("OnEvent", function(_, event, arg1, _, arg3)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then
            return
        end
        VergiShieldRingDB = type(VergiShieldRingDB) == "table" and VergiShieldRingDB or {}
        db = VergiShieldRingDB
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then
                db[k] = v
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        layout()
        setLocked(db.locked)
        -- AishCore peut construire son cercle un peu plus tard.
        C_Timer.After(2, function()
            layout()
            refresh()
        end)
        refresh()
    elseif not db then
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        applyAlpha()
        -- Auras de nouveau lisibles : on efface l'arc si le debuff est fini.
        refresh()
    elseif event == "PLAYER_REGEN_DISABLED" then
        applyAlpha()
        -- Le cercle d'AishCore apparaît en combat : on mémorise sa place.
        C_Timer.After(0.5, function()
            if remember() then
                layout()
                update()
            end
        end)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local id = arg3
        if id ~= nil and not isSecret(id) and PWS_BASE[id] then
            -- Pas d'Âme affaiblie ici : la cible peut être un allié.
            -- L'arc démarre quand un bouclier apparaît sur toi (startShield).
            state.castAt = GetTime()
            -- La valeur du bouclier arrive juste après le sort.
            C_Timer.After(0.1, refresh)
            root:Show()
        end
    elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" then
        refresh()
    elseif event == "UNIT_AURA" then
        refresh()
    end
end)

---------------------------------------------------------------------------
-- Commandes : /vsr
---------------------------------------------------------------------------

local function say(msg)
    print("|cffffe86eFT - Shield Ring|r : " .. msg)
end


---------------------------------------------------------------------------
-- Alerte Mot de l'ombre : Mort
-- La vie de la cible est cachée aux addons en combat. Le jeu accepte pourtant de la mettre dans
-- une barre : un voile sombre (barre) recouvre l'icône tant que la vie de la cible est au-dessus
-- des dégâts minimum du sort, et disparaît quand le sort la tuera. Les dégâts sont lus hors combat.
---------------------------------------------------------------------------

local SWD_ID = 1309595 -- numéro dans Forever (32379 ailleurs)
local SWD_NAMES = { "Mot de l'ombre : Mort", "Mot de l’ombre : Mort", "Shadow Word: Death" }
local swd = { id = nil, dmg = nil, icon = nil }

local alert = CreateFrame("Frame", "FTShieldRingAlert", UIParent)
alert:SetSize(30, 30)
alert:SetFrameStrata("MEDIUM")
alert:Hide()
local glow = alert:CreateTexture(nil, "BACKGROUND")
glow:SetTexture(MEDIA .. "Glow")
glow:SetPoint("CENTER")
glow:SetSize(78, 78)
glow:SetVertexColor(0.7, 0.4, 1, 0)
local aIcon = alert:CreateTexture(nil, "ARTWORK")
aIcon:SetAllPoints()
aIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
local aEdge = alert:CreateTexture(nil, "BORDER")
aEdge:SetPoint("TOPLEFT", -2, 2)
aEdge:SetPoint("BOTTOMRIGHT", 2, -2)
aEdge:SetColorTexture(0.78, 0.56, 1, 1)
local cover = CreateFrame("StatusBar", nil, alert)
cover:SetAllPoints(aIcon)
cover:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
cover:SetStatusBarColor(0, 0, 0, 0.78)
cover:SetOrientation("VERTICAL")
cover:SetFrameLevel(alert:GetFrameLevel() + 2)

local curve, curveFor, curveOk = nil, nil, true

local function normName(n)
    -- apostrophe typographique et espace insécable (Forever : « l’ombre », « Mort » précédé de \194\160)
    return (n:gsub("\226\128\153", "'"):gsub("\194\160", " "):gsub("%s+", " "):lower())
end

-- Cherche Mot de l'ombre : Mort dans le grimoire (le numéro du sort diffère dans Forever).
local function swdKnown()
    local wanted = {}
    for _, n in ipairs(SWD_NAMES) do
        wanted[normName(n)] = true
    end
    local SB = C_SpellBook
    if SB and SB.GetNumSpellBookSkillLines and Enum and Enum.SpellBookSpellBank then
        local bank = Enum.SpellBookSpellBank.Player
        local bestId, bestIcon, bestRank = nil, nil, -1
        for line = 1, SB.GetNumSpellBookSkillLines() do
            local info = SB.GetSpellBookSkillLineInfo(line)
            if info then
                local first = (info.itemIndexOffset or 0) + 1
                for i = first, first + (info.numSpellBookItems or 0) - 1 do
                    local ok, it = pcall(SB.GetSpellBookItemInfo, i, bank)
                    local nm, sub = SB.GetSpellBookItemName(i, bank)
                    nm = nm or (ok and it and it.name)
                    if ok and it and type(nm) == "string" and not isSecret(nm) and wanted[normName(nm)] then
                        local r = sub and tonumber(tostring(sub):match("%d+")) or 0
                        if r > bestRank then
                            bestRank, bestId, bestIcon = r, it.actionID or it.spellID, it.iconID
                        end
                    end
                end
            end
        end
        if bestId then
            return bestId, bestIcon
        end
    end
    if GetNumSpellTabs and GetSpellBookItemName then
        local bestId, bestRank = nil, -1
        for tab = 1, GetNumSpellTabs() do
            local _, _, offset, num = GetSpellTabInfo(tab)
            for i = (offset or 0) + 1, (offset or 0) + (num or 0) do
                local nm, sub = GetSpellBookItemName(i, "spell")
                if type(nm) == "string" and wanted[normName(nm)] then
                    local _, id = GetSpellBookItemInfo(i, "spell")
                    local r = sub and tonumber(tostring(sub):match("%d+")) or 0
                    if id and r > bestRank then
                        bestRank, bestId = r, id
                    end
                end
            end
        end
        if bestId then
            return bestId
        end
    end
    for _, n in ipairs(SWD_NAMES) do
        if C_Spell and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, n)
            if ok and info and info.spellID and (not IsPlayerSpell or IsPlayerSpell(info.spellID)) then
                return info.spellID, info.iconID
            end
        end
    end
    for _, id in ipairs({ SWD_ID, 32379 }) do
        if IsPlayerSpell and IsPlayerSpell(id) then
            return id
        end
    end
end

-- Hors combat : sort connu ? dégâts minimum lus dans sa description.
local function readSwd()
    if InCombatLockdown() then
        return
    end
    local id, icon = swdKnown()
    swd.id, swd.icon = id, icon
    swd.dmg = nil
    if id and C_Spell and C_Spell.GetSpellDescription then
        local ok, desc = pcall(C_Spell.GetSpellDescription, id)
        if ok and type(desc) == "string" and not isSecret(desc) then
            local n = desc:gsub("[%s\194\160\226\128\175]", ""):match("(%d+)")
            swd.dmg = tonumber(n)
        end
    end
    if not swd.icon and C_Spell and C_Spell.GetSpellTexture and id then
        swd.icon = C_Spell.GetSpellTexture(id)
    end
end

local function threshold()
    if db and (db.swdTest or 0) > 0 then
        return db.swdTest
    end
    return swd.dmg
end

local function placeAlert()
    alert:ClearAllPoints()
    alert:SetPoint("BOTTOM", root, "CENTER", 0, radius() + (db and db.dotSize or 7) + 16)
end

local function setGlow(thr)
    if not curveOk or not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then
        glow:Hide()
        return
    end
    local ok = pcall(function()
        if curveFor ~= thr then
            curve = C_CurveUtil.CreateColorCurve()
            if curve.SetType and Enum and Enum.LuaCurveType then
                curve:SetType(Enum.LuaCurveType.Step)
            end
            curve:AddPoint(0, CreateColor(0.7, 0.4, 1, 1))
            curve:AddPoint(thr, CreateColor(0.7, 0.4, 1, 0))
            curveFor = thr
        end
        local c = curve:Evaluate(UnitHealth("target"))
        glow:SetVertexColor(c:GetRGBA())
    end)
    if ok then
        glow:Show()
    else
        curveOk = false
        glow:Hide()
    end
end

local function alertActive()
    if not db or db.swdAlert == false then
        return false
    end
    local thr = threshold()
    if not thr or thr <= 1 then
        return false
    end
    if not (db.swdTest and db.swdTest > 0) and not swd.id then
        return false
    end
    if not InCombatLockdown() or not UnitExists("target") or not UnitCanAttack("player", "target") then
        return false
    end
    local ok, dead = pcall(UnitIsDeadOrGhost, "target")
    if ok and dead == true then
        return false
    end
    return true, thr
end

local aTick = 0
local function updateAlert()
    local on, thr = alertActive()
    if not on then
        alert:Hide()
        return
    end
    aIcon:SetTexture(swd.icon or "Interface\\Icons\\Spell_Shadow_DemonicFortitude")
    cover:SetMinMaxValues(thr - 1, thr)
    pcall(cover.SetValue, cover, UnitHealth("target"))
    setGlow(thr)
    alert:Show()
end


local aEv = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_TARGET_CHANGED", "SPELLS_CHANGED", "UNIT_INVENTORY_CHANGED" }) do
    pcall(aEv.RegisterEvent, aEv, e)
end
aEv:SetScript("OnEvent", function(_, e)
    if not db then
        return
    end
    if e ~= "PLAYER_REGEN_DISABLED" and e ~= "PLAYER_TARGET_CHANGED" then
        readSwd()
    end
    placeAlert()
    updateAlert()
end)


---------------------------------------------------------------------------
-- Âme affaiblie du groupe : 4 tirets en demi-cercle sous l'anneau, dans l'ordre des cadres HealKit.
-- Doré = bouclier possible. Rouge = Âme affaiblie (n'importe quel prêtre) : c'est le jeu qui
-- affiche le tiret rouge (AuraContainer), même en combat.
---------------------------------------------------------------------------

local WS_IDS = { 6788 }
local PARTY_SLOTS = 4
local partyHolder = CreateFrame("Frame", "FTShieldRingParty", UIParent)
partyHolder:SetSize(1, 1)
partyHolder:SetFrameStrata("MEDIUM")
partyHolder:Hide()
local slots = {}
local slotUnits = {}
local partyDirty = true
local FlowDir = AnchorUtil and AnchorUtil.FlowDirection

local ROLE_RANK = { TANK = 1, HEALER = 2, DAMAGER = 3 }
local function roleRank(unit)
    local ok, r = pcall(UnitGroupRolesAssigned, unit)
    return (ok and ROLE_RANK[r or ""]) or 3
end

-- Membres suivis, dans l'ordre des cadres HealKit (tri par rôle si HealKit trie par rôle).
local function trackedUnits()
    local sortBy = type(HealKitDB) == "table" and HealKitDB.sortBy or "role"
    local list = {}
    if IsInRaid() then
        for i = 1, 40 do
            local u = "raid" .. i
            if UnitExists(u) and not UnitIsUnit(u, "player") and roleRank(u) == 1 then
                local _, _, sub = GetRaidRosterInfo(i)
                list[#list + 1] = { u = u, r = sub or 9, i = i }
            end
        end
        table.sort(list, function(a, b)
            if a.r ~= b.r then
                return a.r < b.r
            end
            return a.i < b.i
        end)
        local out = {}
        for k = 1, math.min(3, #list) do
            out[#out + 1] = list[k].u
        end
        if UnitExists("focus") and not UnitIsUnit("focus", "player") then
            local dup = false
            for _, u in ipairs(out) do
                if UnitIsUnit(u, "focus") then
                    dup = true
                end
            end
            if not dup then
                out[#out + 1] = "focus"
            end
        end
        return out
    end
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) then
            list[#list + 1] = { u = u, r = (sortBy == "role") and roleRank(u) or 1, i = i }
        end
    end
    table.sort(list, function(a, b)
        if a.r ~= b.r then
            return a.r < b.r
        end
        return a.i < b.i
    end)
    local out = {}
    for _, e in ipairs(list) do
        out[#out + 1] = e.u
    end
    return out
end

local function slotGeometry(i)
    local wr = radius() + (db and db.dotSize or 7) + 2
    local R = wr + 12
    local ang = math.rad(180 + (i - 0.5) * 180 / PARTY_SLOTS)
    local len = math.max(10, R * math.rad(30))
    return math.cos(ang) * R, math.sin(ang) * R, ang + math.pi / 2, len
end

local function makeSlot(i)
    local s = {}
    s.base = partyHolder:CreateTexture(nil, "ARTWORK")
    s.base:SetTexture("Interface\\Buttons\\WHITE8x8")
    s.base:SetVertexColor(0.91, 0.78, 0.42, 0.9)
    if FlowDir then
        local ok, c = pcall(CreateFrame, "AuraContainer", nil, partyHolder, "CustomAuraContainerTemplate")
        if ok and c then
            local done = pcall(function()
                c:SetSize(24, 24)
                c:SetFrameLevel(partyHolder:GetFrameLevel() + 5)
                c:SetFlowLayoutAnchorPoint("TOPLEFT")
                c:SetFlowLayoutGrowthDirection(FlowDir.Right, FlowDir.Down)
                c:EnableMouse(false)
                if c.SetEditModePreviewEnabled then
                    c:SetEditModePreviewEnabled(false)
                end
                c:AddAuraGroup("ws", "HARMFUL", {
                    maxFrameCount = 1,
                    templateNames = { "FTShieldRingWSDashTemplate" },
                    initializeFrame = function(btn)
                        local _, _, rot, len = slotGeometry(i)
                        btn:SetSize(24, 24)
                        if btn.Dash then
                            btn.Dash:SetSize(len, 4)
                            btn.Dash:SetRotation(rot)
                        end
                    end,
                    candidateFilters = { includeSpellIDs = WS_IDS },
                    layout = { elementSpacing = 0 },
                })
                c:SetUnit("none")
            end)
            if done then
                s.cont = c
            else
                c:Hide()
            end
        end
    end
    slots[i] = s
    return s
end

local function placeParty()
    partyHolder:ClearAllPoints()
    partyHolder:SetPoint("CENTER", root, "CENTER")
    for i = 1, PARTY_SLOTS do
        local s = slots[i] or makeSlot(i)
        local x, y, rot, len = slotGeometry(i)
        s.base:ClearAllPoints()
        s.base:SetPoint("CENTER", partyHolder, "CENTER", x, y)
        s.base:SetSize(len, 4)
        s.base:SetRotation(rot)
        if s.cont then
            pcall(s.cont.ClearAllPoints, s.cont)
            pcall(s.cont.SetPoint, s.cont, "TOPLEFT", partyHolder, "CENTER", x - 12, y + 12)
        end
    end
end

local function assignParty()
    if InCombatLockdown() then
        partyDirty = true
        return
    end
    partyDirty = false
    local units = trackedUnits()
    for i = 1, PARTY_SLOTS do
        local s = slots[i] or makeSlot(i)
        local u = units[i]
        slotUnits[i] = u
        s.base:SetShown(u ~= nil)
        if s.cont then
            pcall(s.cont.SetUnit, s.cont, u or "none")
            pcall(s.cont.SetShown, s.cont, u ~= nil)
        end
    end
end

local function partyVisible()
    if not db or db.partyWS == false then
        return false
    end
    if state.test then
        return true -- aperçu (/vsr test) : les 4 tirets, même seul
    end
    if not IsInGroup() then
        return false
    end
    return not db.locked or not db.combatOnly or InCombatLockdown()
end

local function updateParty()
    if partyVisible() then
        if state.test and not IsInGroup() then
            for i = 1, PARTY_SLOTS do
                if slots[i] then
                    slots[i].base:Show()
                end
            end
        end
        partyHolder:Show()
    else
        partyHolder:Hide()
    end
end

-- Mise à jour régulière de l'alerte et des tirets (ce cadre reste toujours actif).
local lastGeo
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, e)
    aTick = aTick + e
    if aTick >= 0.1 then
        aTick = 0
        if db then
            local key = radius() .. ":" .. (db.dotSize or 7)
            if key ~= lastGeo then
                lastGeo = key
                placeParty()
                placeAlert()
            end
            updateAlert()
            updateParty()
        end
    end
end)

local pEv = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PLAYER_FOCUS_CHANGED",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }) do
    pcall(pEv.RegisterEvent, pEv, e)
end
pEv:SetScript("OnEvent", function(_, e)
    if not db then
        return
    end
    placeParty()
    if e ~= "PLAYER_REGEN_DISABLED" or partyDirty then
        assignParty()
    end
    updateParty()
end)

local testBar
SLASH_VERGISHIELDRING1 = "/vsr"
SlashCmdList.VERGISHIELDRING = function(msg)
    local cmd, arg = (msg or ""):lower():match("^(%S*)%s*(.-)$")
    if cmd == "test" then
        state.test = not state.test
        if state.test then
            state.max, state.active = 950, true
            setRanges()
            root:Show()
            update()
            updateWS()
            root:SetAlpha(1)
            say("aperçu activé (/vsr test pour arrêter).")
        else
            state.active = false
            refresh()
            setLocked(db.locked)
            assignParty()
            say("aperçu arrêté.")
        end
    elseif cmd == "deplacer" or cmd == "unlock" then
        setLocked(false)
        say("déplace l'anneau à la souris, puis /vsr verrouiller.")
    elseif cmd == "verrouiller" or cmd == "lock" then
        setLocked(true)
        say("position enregistrée.")
    elseif cmd == "couleur" and (PRESETS[arg] or arg == "classe") then
        db.color = arg
        layout()
        update()
        say("couleur : " .. arg .. ".")
    elseif cmd == "ecart" and tonumber(arg) then
        db.gap = tonumber(arg)
        layout()
        update()
        say("écart : " .. db.gap .. ".")
    elseif cmd == "taille" and tonumber(arg) then
        db.dotSize = math.max(3, math.min(20, tonumber(arg)))
        layout()
        update()
        say("taille des points : " .. db.dotSize .. ".")
    elseif cmd == "points" and tonumber(arg) then
        db.dots = math.max(16, math.min(120, math.floor(tonumber(arg))))
        layout()
        update()
        say("nombre de points : " .. db.dots .. ".")
    elseif cmd == "combat" then
        db.combatOnly = not db.combatOnly
        applyAlpha()
        say(db.combatOnly and "visible en combat uniquement." or "visible aussi hors combat.")
    elseif cmd == "temps" then
        db.showTime = not db.showTime
        say("temps restant " .. (db.showTime and "affiché." or "masqué."))
    elseif cmd == "texte" then
        db.showText = not db.showText
        update()
        say("nombre " .. (db.showText and "affiché." or "masqué."))
    elseif cmd == "ame" then
        db.showWS = not db.showWS
        updateWS()
        say("Âme affaiblie " .. (db.showWS and "affichée." or "masquée."))
    elseif cmd == "testvie" then
        -- Test : la vie de la cible et la puissance des sorts sont-elles lisibles (surtout en combat) ?
        local function read(fn, ...)
            if not fn then
                return "absente"
            end
            local ok, v = pcall(fn, ...)
            if not ok then
                return "erreur"
            elseif v == nil then
                return "vide"
            elseif isSecret(v) then
                return "CACHÉE"
            end
            return tostring(v)
        end
        local fight = InCombatLockdown() and "oui" or "non"
        local enemy = UnitExists("target") and UnitCanAttack("player", "target")
        local hp = read(UnitHealth, "target")
        local hpMax = read(UnitHealthMax, "target")
        local sp = read(GetSpellBonusDamage, 6)
        say("test vie : combat " .. fight .. ", cible ennemie " .. (enemy and "oui" or "non"))
        print("  vie de la cible : " .. hp .. " / " .. hpMax)
        print("  puissance des sorts d'Ombre : " .. sp)
        -- Mot de l'ombre : Mort : rang connu et dégâts indiqués dans sa description
        local swdName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(32379)
        local swdId, desc = nil, nil
        if swdName and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, swdName)
            swdId = ok and info and info.spellID
        end
        if swdId and C_Spell.GetSpellDescription then
            local ok, d = pcall(C_Spell.GetSpellDescription, swdId)
            desc = ok and d or nil
            if desc and isSecret(desc) then
                desc = "CACHÉE"
            end
        end
        print("  Mot de l'ombre : Mort : " .. (swdId and ("connu (sort " .. swdId .. ")") or "non trouvé"))
        if desc then
            print("  description : " .. tostring(desc):gsub("\n", " "))
        end
        -- Barre cachée : le jeu accepte-t-il d'y mettre la vie (cachée) de la cible ?
        local barOk = "pas de cible"
        if UnitExists("target") then
            testBar = testBar or CreateFrame("StatusBar", nil, UIParent)
            local bar = testBar
            bar:Hide()
            bar:SetMinMaxValues(0, 1000)
            local ok = pcall(bar.SetValue, bar, UnitHealth("target"))
            barOk = ok and "OUI" or "non"
        end
        print("  barre de vie cachée acceptée : " .. barOk)
        print("  outils du jeu : UnitHealthPercent " .. (UnitHealthPercent and "oui" or "non")
            .. ", courbes " .. ((C_CurveUtil and "oui") or "non"))
        if not enemy then
            print("  |cffffd24aCible un monstre et relance le test en combat.|r")
        elseif fight == "oui" then
            local ok = hp ~= "CACHÉE" and hp ~= "erreur" and hp ~= "vide" and hp ~= "absente"
            print(ok and "  |cff6fd06fLisible en combat : l'alerte Mot de l'ombre : Mort est possible.|r"
                or "  |cffff5555Cachée en combat : l'alerte ne pourra pas calculer si la cible meurt.|r")
        end
        db.testvie = db.testvie or {}
        db.testvie[#db.testvie + 1] = { t = time(), combat = fight, enemy = enemy and true or false, hp = hp, hpMax = hpMax, sp = sp, swd = swdId, desc = desc and tostring(desc) or nil, bar = barOk, pct = UnitHealthPercent and true or false, curve = C_CurveUtil and true or false }
        while #db.testvie > 10 do
            table.remove(db.testvie, 1)
        end
    elseif cmd == "seuil" then
        local n = tonumber(arg)
        if n and n >= 0 then
            db.swdTest = n
            say(n > 0 and ("alerte en mode test : s'allume quand la cible passe sous " .. n .. " PV (en combat). /vsr seuil 0 pour arrêter.")
                or "mode test de l'alerte arrêté.")
        else
            say("usage : /vsr seuil <PV> (0 = arrêter le test)")
        end
    elseif cmd == "mort" then
        db.swdAlert = db.swdAlert == false
        readSwd()
        say("alerte Mot de l'ombre : Mort " .. (db.swdAlert ~= false and "activée" or "désactivée")
            .. (swd.id and (swd.dmg and (" (dégâts minimum lus : " .. swd.dmg .. ")") or " (dégâts non lus)") or " (sort pas encore appris)") .. ".")
    elseif cmd == "debugmort" then
        local SB = C_SpellBook
        say("diagnostic grimoire : C_SpellBook " .. (SB and "oui" or "non") .. ", ancienne API " .. (GetNumSpellTabs and "oui" or "non"))
        local found = 0
        local function show(src, i, nm, sub, id)
            local low = type(nm) == "string" and normName(nm) or ""
            if low:find("mort", 1, true) or low:find("death", 1, true) then
                found = found + 1
                local bytes = {}
                for k = 1, math.min(#nm, 40) do
                    bytes[#bytes + 1] = nm:byte(k)
                end
                print(string.format("  [%s %d] %s | %s | sort %s | octets %s", src, i, nm, tostring(sub), tostring(id), table.concat(bytes, ",")))
            end
        end
        if SB and SB.GetNumSpellBookSkillLines and Enum and Enum.SpellBookSpellBank then
            local bank = Enum.SpellBookSpellBank.Player
            local lines = SB.GetNumSpellBookSkillLines()
            print("  lignes du grimoire : " .. tostring(lines))
            for line = 1, lines do
                local info = SB.GetSpellBookSkillLineInfo(line)
                if info then
                    local first = (info.itemIndexOffset or 0) + 1
                    for i = first, first + (info.numSpellBookItems or 0) - 1 do
                        local ok, it = pcall(SB.GetSpellBookItemInfo, i, bank)
                        local nm, sub = SB.GetSpellBookItemName(i, bank)
                        show("SB", i, nm or (ok and it and it.name), sub, ok and it and (it.actionID or it.spellID))
                    end
                end
            end
        end
        if GetNumSpellTabs and GetSpellBookItemName then
            for tab = 1, GetNumSpellTabs() do
                local _, _, offset, num = GetSpellTabInfo(tab)
                for i = (offset or 0) + 1, (offset or 0) + (num or 0) do
                    local nm, sub = GetSpellBookItemName(i, "spell")
                    local _, id = GetSpellBookItemInfo(i, "spell")
                    show("ancien", i, nm, sub, id)
                end
            end
        end
        print("  sorts trouvés contenant « mort » : " .. found)
    elseif cmd == "groupe" then
        db.partyWS = db.partyWS == false
        placeParty()
        assignParty()
        updateParty()
        say("tirets Âme affaiblie du groupe " .. (db.partyWS and "affichés." or "masqués."))
    elseif cmd == "reset" then
        for k, v in pairs(DEFAULTS) do
            db[k] = v
        end
        db.ax, db.ay, db.ar = nil, nil, nil
        layout()
        setLocked(true)
        say("réglages par défaut.")
    else
        say("commandes :")
        print("  /vsr test — aperçu de l'anneau")
        print("  /vsr deplacer — déplacer à la souris, puis /vsr verrouiller")
        print("  /vsr couleur sacre|ombre|givre|naaru|classe")
        print("  /vsr ecart <px> — écart avec le cercle de vie (défaut 10)")
        print("  /vsr taille <px> — taille des points (défaut 7)")
        print("  /vsr points <n> — nombre de points (défaut 64)")
        print("  /vsr combat — visible en combat uniquement (oui/non)")
        print("  /vsr texte — afficher/masquer le nombre")
        print("  /vsr temps — afficher/masquer le temps restant du bouclier")
        print("  /vsr ame — afficher/masquer Âme affaiblie")
        print("  /vsr groupe — tirets Âme affaiblie du groupe (oui/non)")
        print("  /vsr mort — alerte Mot de l'ombre : Mort (oui/non)")
        print("  /vsr seuil <PV> — tester l'alerte avec un seuil fixe (0 = arrêter)")
        print("  /vsr testvie — test : vie de la cible lisible en combat ?")
        print("  /vsr reset — réglages par défaut")
    end
end
