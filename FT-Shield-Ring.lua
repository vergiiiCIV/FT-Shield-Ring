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
        print("  /vsr reset — réglages par défaut")
    end
end
