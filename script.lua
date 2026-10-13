-- MestreAfiado Hub | ServerHop + Navegador + Evitar Jogadores (com perfil)
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer

-- ============================================================
-- PROTEÇÃO contra loops de versões antigas
-- ============================================================
if getgenv then
    getgenv().MA_Stop = true
    task.wait(0.15)
    getgenv().MA_Stop = false
end

-- ============================================================
-- CONFIG
-- ============================================================
local autoHopAtivo = false
local limitePlayers = 3
local emHop = false
local servidoresVisitados = {}
local entrouEm = os.clock()
local CARENCIA_SEGUNDOS = 15
local COOLDOWN_HOP = 8
local ultimoHop = 0
local SCRIPT_URL = "" -- auto-injeção no próximo server (opcional)

-- Evitados: por UserId (robusto) + por nome
local evitadosLista = {}            -- array de {key, name, display, userId}
local evitadosPorNome = {}          -- key(nick minúsculo) -> entry
local evitadosPorUserId = {}        -- userId -> true

-- ============================================================
-- HTTP com rotação de PROXY (resolve o "Bloqueio na API")
-- ============================================================
local function rawRequest(url, method, body)
    method = method or "GET"
    local reqFns = { request, http_request, syn and syn.request, fluxus and fluxus.request }
    for _, fn in ipairs(reqFns) do
        if type(fn) == "function" then
            local ok, res = pcall(function()
                return fn({
                    Url = url,
                    Method = method,
                    Headers = {
                        ["User-Agent"] = "Roblox/WinInet",
                        ["Referer"] = "https://www.roblox.com/",
                        ["Content-Type"] = "application/json",
                    },
                    Body = body,
                })
            end)
            if ok and res and type(res) == "table" then
                local sc = res.StatusCode or res.status_code or 200
                if res.Body and res.Body ~= "" and sc < 400 then return res.Body end
            end
        end
    end
    if method == "GET" then
        local ok, res = pcall(function() return game:HttpGet(url, true) end)
        if ok and res and res ~= "" then return res end
    end
    return nil
end

-- sub = "games" | "users" | "thumbnails" ; path = "/v1/..."
local PROXY_BUILDERS = {
    function(sub, path) return "https://" .. sub .. ".roblox.com" .. path end,
    function(sub, path) return "https://" .. sub .. ".roproxy.com" .. path end,
    function(sub, path) return "https://rprxy.xyz/" .. sub .. path end,
    function(sub, path) return "https://roblox-proxy.f5.si/" .. sub .. path end,
}

local function apiGet(sub, path)
    for _, build in ipairs(PROXY_BUILDERS) do
        local body = rawRequest(build(sub, path), "GET")
        if body then
            local ok, json = pcall(function() return HttpService:JSONDecode(body) end)
            if ok and json and type(json) == "table" and not json.errors then
                return json
            end
        end
    end
    return nil
end

local function apiPost(sub, path, bodyTable)
    local jsonBody = HttpService:JSONEncode(bodyTable)
    for _, build in ipairs(PROXY_BUILDERS) do
        local body = rawRequest(build(sub, path), "POST", jsonBody)
        if body then
            local ok, json = pcall(function() return HttpService:JSONDecode(body) end)
            if ok and json and type(json) == "table" and not json.errors then
                return json
            end
        end
    end
    return nil
end

-- Resolve nick -> perfil real (name, displayName, id)
local function resolverPerfil(nome)
    local json = apiPost("users", "/v1/usernames/users", {
        usernames = { nome },
        excludeBannedUsers = false,
    })
    if json and json.data and #json.data > 0 then
        local d = json.data[1]
        return { name = d.name, display = d.displayName, userId = d.id }
    end
    return nil
end

-- ============================================================
-- Onde injetar a GUI
-- ============================================================
local targetGui
pcall(function()
    if gethui then targetGui = gethui()
    elseif cloneref and CoreGui then targetGui = cloneref(CoreGui)
    elseif CoreGui then targetGui = CoreGui
    else targetGui = player:WaitForChild("PlayerGui", 5) end
end)
if not targetGui then targetGui = player:WaitForChild("PlayerGui") end

for _, child in ipairs(targetGui:GetChildren()) do
    if child.Name == "MestreAfiado_ServerHop" then child:Destroy() end
end

-- ============================================================
-- GUI PRINCIPAL
-- ============================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MestreAfiado_ServerHop"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 999999
screenGui.IgnoreGuiInset = true
screenGui.Parent = targetGui
pcall(function() if syn and syn.protect_gui then syn.protect_gui(screenGui) end end)

local openBtn = Instance.new("TextButton")
openBtn.Size = UDim2.new(0, 48, 0, 48)
openBtn.Position = UDim2.new(0.05, 0, 0.2, 0)
openBtn.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
openBtn.Text = "MH"
openBtn.TextColor3 = Color3.fromRGB(255, 42, 75)
openBtn.Font = Enum.Font.GothamBold
openBtn.TextSize = 16
openBtn.Active = true
openBtn.Draggable = true
openBtn.Parent = screenGui
Instance.new("UICorner", openBtn).CornerRadius = UDim.new(0,12)
local os_ = Instance.new("UIStroke"); os_.Color = Color3.fromRGB(255,255,255); os_.Thickness = 2; os_.Parent = openBtn

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 330, 0, 290)
mainFrame.Position = UDim2.new(0.5, -165, 0.5, -145)
mainFrame.BackgroundColor3 = Color3.fromRGB(22, 22, 32)
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Visible = true
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0,10)
local ms = Instance.new("UIStroke"); ms.Color = Color3.fromRGB(255,255,255); ms.Thickness = 1.5; ms.Parent = mainFrame

local headerTitle = Instance.new("TextLabel")
headerTitle.Size = UDim2.new(1, -40, 0, 35)
headerTitle.Position = UDim2.new(0, 10, 0, 0)
headerTitle.BackgroundTransparency = 1
headerTitle.Text = "MestreAfiado Hub | ServerHop"
headerTitle.TextColor3 = Color3.fromRGB(255,255,255)
headerTitle.Font = Enum.Font.GothamBold
headerTitle.TextSize = 13
headerTitle.TextXAlignment = Enum.TextXAlignment.Center
headerTitle.Parent = mainFrame

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 25, 0, 25)
closeBtn.Position = UDim2.new(1, -30, 0, 5)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "x"
closeBtn.TextColor3 = Color3.fromRGB(255,80,80)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.Parent = mainFrame
closeBtn.MouseButton1Click:Connect(function() mainFrame.Visible = false end)
openBtn.MouseButton1Click:Connect(function() mainFrame.Visible = not mainFrame.Visible end)

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -20, 0, 25)
statusLabel.Position = UDim2.new(0, 10, 0, 35)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Jogadores neste servidor: " .. #Players:GetPlayers()
statusLabel.TextColor3 = Color3.fromRGB(50, 220, 80)
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextSize = 12
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Parent = mainFrame

local avisarTela = Instance.new("TextLabel")
avisarTela.Size = UDim2.new(0, 320, 0, 45)
avisarTela.Position = UDim2.new(0.5, -160, 0.15, 0)
avisarTela.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
avisarTela.Text = ""
avisarTela.TextColor3 = Color3.fromRGB(255,255,255)
avisarTela.Font = Enum.Font.GothamBold
avisarTela.TextSize = 14
avisarTela.Visible = false
avisarTela.Parent = screenGui
Instance.new("UICorner", avisarTela).CornerRadius = UDim.new(0,8)
local avs = Instance.new("UIStroke"); avs.Color = Color3.fromRGB(255,255,255); avs.Thickness = 2; avs.Parent = avisarTela

local function mostrarAviso(texto, cor, tempo)
    avisarTela.Visible = true
    avisarTela.Text = texto
    avisarTela.TextColor3 = cor
    if tempo then
        task.delay(tempo, function()
            if avisarTela.Text == texto then avisarTela.Visible = false end
        end)
    end
end

local infoLabel = Instance.new("TextLabel")
infoLabel.Size = UDim2.new(1, -20, 0, 20)
infoLabel.Position = UDim2.new(0, 10, 0, 60)
infoLabel.BackgroundTransparency = 1
infoLabel.Text = "Pronto para procurar."
infoLabel.TextColor3 = Color3.fromRGB(150,150,170)
infoLabel.Font = Enum.Font.Gotham
infoLabel.TextSize = 11
infoLabel.TextXAlignment = Enum.TextXAlignment.Left
infoLabel.Parent = mainFrame

local subInfoLabel = Instance.new("TextLabel")
subInfoLabel.Size = UDim2.new(1, -20, 0, 20)
subInfoLabel.Position = UDim2.new(0, 10, 0, 85)
subInfoLabel.BackgroundTransparency = 1
subInfoLabel.Text = "Hop se jogadores no server forem MAIS que:"
subInfoLabel.TextColor3 = Color3.fromRGB(150,150,170)
subInfoLabel.Font = Enum.Font.Gotham
subInfoLabel.TextSize = 11
subInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
subInfoLabel.Parent = mainFrame

local textBox = Instance.new("TextBox")
textBox.Size = UDim2.new(1, -20, 0, 30)
textBox.Position = UDim2.new(0, 10, 0, 110)
textBox.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
textBox.Text = tostring(limitePlayers)
textBox.TextColor3 = Color3.fromRGB(255,255,255)
textBox.Font = Enum.Font.GothamBold
textBox.TextSize = 14
textBox.Parent = mainFrame
Instance.new("UICorner", textBox).CornerRadius = UDim.new(0,6)
textBox.FocusLost:Connect(function()
    local num = tonumber(textBox.Text)
    if num then limitePlayers = math.clamp(math.floor(num), 1, 50) end
    textBox.Text = tostring(limitePlayers)
end)

-- Toggle 1: Navegador
local toggleLabel = Instance.new("TextLabel")
toggleLabel.Size = UDim2.new(0, 230, 0, 30)
toggleLabel.Position = UDim2.new(0, 10, 0, 145)
toggleLabel.BackgroundTransparency = 1
toggleLabel.Text = "Navegador de Servidores"
toggleLabel.TextColor3 = Color3.fromRGB(220,220,230)
toggleLabel.Font = Enum.Font.Gotham
toggleLabel.TextSize = 11
toggleLabel.TextXAlignment = Enum.TextXAlignment.Left
toggleLabel.Parent = mainFrame

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(0, 50, 0, 24)
toggleBtn.Position = UDim2.new(1, -60, 0, 148)
toggleBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
toggleBtn.Text = ""
toggleBtn.Parent = mainFrame
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(1,0)
local toggleCircle = Instance.new("Frame")
toggleCircle.Size = UDim2.new(0, 18, 0, 18)
toggleCircle.Position = UDim2.new(0, 3, 0.5, -9)
toggleCircle.BackgroundColor3 = Color3.fromRGB(255,255,255)
toggleCircle.Parent = toggleBtn
Instance.new("UICorner", toggleCircle).CornerRadius = UDim.new(1,0)

-- Toggle 2: Evitar Jogadores
local avoidToggleLabel = Instance.new("TextLabel")
avoidToggleLabel.Size = UDim2.new(0, 230, 0, 30)
avoidToggleLabel.Position = UDim2.new(0, 10, 0, 178)
avoidToggleLabel.BackgroundTransparency = 1
avoidToggleLabel.Text = "Evitar Jogadores (Auto-Hop)"
avoidToggleLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
avoidToggleLabel.Font = Enum.Font.Gotham
avoidToggleLabel.TextSize = 11
avoidToggleLabel.TextXAlignment = Enum.TextXAlignment.Left
avoidToggleLabel.Parent = mainFrame

local avoidToggleBtn = Instance.new("TextButton")
avoidToggleBtn.Size = UDim2.new(0, 50, 0, 24)
avoidToggleBtn.Position = UDim2.new(1, -60, 0, 181)
avoidToggleBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
avoidToggleBtn.Text = ""
avoidToggleBtn.Parent = mainFrame
Instance.new("UICorner", avoidToggleBtn).CornerRadius = UDim.new(1,0)
local avoidToggleCircle = Instance.new("Frame")
avoidToggleCircle.Size = UDim2.new(0, 18, 0, 18)
avoidToggleCircle.Position = UDim2.new(0, 3, 0.5, -9)
avoidToggleCircle.BackgroundColor3 = Color3.fromRGB(255,255,255)
avoidToggleCircle.Parent = avoidToggleBtn
Instance.new("UICorner", avoidToggleCircle).CornerRadius = UDim.new(1,0)

-- ============================================================
-- NAVEGADOR DE SERVIDORES (com COPY + proxy)
-- ============================================================
local browserFrame = Instance.new("Frame")
browserFrame.Size = UDim2.new(0, 340, 0, 360)
browserFrame.Position = UDim2.new(0.5, -170, 0.5, -180)
browserFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
browserFrame.Active = true
browserFrame.Draggable = true
browserFrame.Visible = false
browserFrame.Parent = screenGui
Instance.new("UICorner", browserFrame).CornerRadius = UDim.new(0,10)
local bs = Instance.new("UIStroke"); bs.Color = Color3.fromRGB(255,255,255); bs.Thickness = 1.5; bs.Parent = browserFrame

local browserHeader = Instance.new("TextLabel")
browserHeader.Size = UDim2.new(0, 200, 0, 25)
browserHeader.Position = UDim2.new(0, 15, 0, 10)
browserHeader.BackgroundTransparency = 1
browserHeader.Text = "NAVEGADOR DE SERVIDORES"
browserHeader.TextColor3 = Color3.fromRGB(255,255,255)
browserHeader.Font = Enum.Font.GothamBold
browserHeader.TextSize = 13
browserHeader.TextXAlignment = Enum.TextXAlignment.Left
browserHeader.Parent = browserFrame

local browserSubHeader = Instance.new("TextLabel")
browserSubHeader.Size = UDim2.new(0, 200, 0, 18)
browserSubHeader.Position = UDim2.new(0, 15, 0, 32)
browserSubHeader.BackgroundTransparency = 1
browserSubHeader.Text = "Clique em atualizar."
browserSubHeader.TextColor3 = Color3.fromRGB(140,140,160)
browserSubHeader.Font = Enum.Font.Gotham
browserSubHeader.TextSize = 11
browserSubHeader.TextXAlignment = Enum.TextXAlignment.Left
browserSubHeader.Parent = browserFrame

local refreshBtn = Instance.new("TextButton")
refreshBtn.Size = UDim2.new(0, 80, 0, 28)
refreshBtn.Position = UDim2.new(1, -95, 0, 12)
refreshBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
refreshBtn.Text = "ATUALIZAR"
refreshBtn.TextColor3 = Color3.fromRGB(255,255,255)
refreshBtn.Font = Enum.Font.GothamBold
refreshBtn.TextSize = 10
refreshBtn.Parent = browserFrame
Instance.new("UICorner", refreshBtn).CornerRadius = UDim.new(0,6)

local scrollList = Instance.new("ScrollingFrame")
scrollList.Size = UDim2.new(1, -20, 1, -65)
scrollList.Position = UDim2.new(0, 10, 0, 55)
scrollList.BackgroundTransparency = 1
scrollList.ScrollBarThickness = 4
scrollList.CanvasSize = UDim2.new(0, 0, 0, 0)
scrollList.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollList.Parent = browserFrame
local ull = Instance.new("UIListLayout")
ull.SortOrder = Enum.SortOrder.LayoutOrder
ull.Padding = UDim.new(0, 8)
ull.Parent = scrollList

local atualizandoBrowser = false
local function carregarNavegador()
    if atualizandoBrowser then return end
    atualizandoBrowser = true
    refreshBtn.Text = "..."
    for _, child in ipairs(scrollList:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
    browserSubHeader.Text = "Buscando servidores..."

    task.spawn(function()
        local placeId = game.PlaceId
        local path = "/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&limit=100"
        local result = apiGet("games", path)
        atualizandoBrowser = false
        refreshBtn.Text = "ATUALIZAR"

        if result and result.data then
            local count = 0
            for _, v in ipairs(result.data) do
                if type(v) == "table" and v.playing and v.maxPlayers and v.id then
                    count = count + 1
                    local card = Instance.new("Frame")
                    card.Size = UDim2.new(1, -6, 0, 55)
                    card.BackgroundColor3 = Color3.fromRGB(26, 26, 38)
                    card.Parent = scrollList
                    Instance.new("UICorner", card).CornerRadius = UDim.new(0,6)

                    local bar = Instance.new("Frame")
                    bar.Size = UDim2.new(0, 4, 1, -12)
                    bar.Position = UDim2.new(0, 6, 0, 6)
                    bar.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
                    bar.Parent = card
                    Instance.new("UICorner", bar).CornerRadius = UDim.new(1,0)

                    local infoText = Instance.new("TextLabel")
                    infoText.Size = UDim2.new(0, 120, 0, 22)
                    infoText.Position = UDim2.new(0, 18, 0, 6)
                    infoText.BackgroundTransparency = 1
                    infoText.Text = v.playing .. " / " .. v.maxPlayers .. " jogadores"
                    infoText.TextColor3 = Color3.fromRGB(255,255,255)
                    infoText.Font = Enum.Font.GothamBold
                    infoText.TextSize = 13
                    infoText.TextXAlignment = Enum.TextXAlignment.Left
                    infoText.Parent = card

                    local subText = Instance.new("TextLabel")
                    subText.Size = UDim2.new(0, 120, 0, 18)
                    subText.Position = UDim2.new(0, 18, 0, 28)
                    subText.BackgroundTransparency = 1
                    subText.Text = "ID: " .. string.sub(v.id, 1, 10) .. "..."
                    subText.TextColor3 = Color3.fromRGB(130,130,150)
                    subText.Font = Enum.Font.Gotham
                    subText.TextSize = 10
                    subText.TextXAlignment = Enum.TextXAlignment.Left
                    subText.Parent = card

                    local copyBtn = Instance.new("TextButton")
                    copyBtn.Size = UDim2.new(0, 62, 0, 35)
                    copyBtn.Position = UDim2.new(1, -162, 0.5, -17)
                    copyBtn.BackgroundColor3 = Color3.fromRGB(90, 90, 130)
                    copyBtn.Text = "COPY"
                    copyBtn.TextColor3 = Color3.fromRGB(255,255,255)
                    copyBtn.Font = Enum.Font.GothamBold
                    copyBtn.TextSize = 10
                    copyBtn.Parent = card
                    Instance.new("UICorner", copyBtn).CornerRadius = UDim.new(0,6)
                    copyBtn.MouseButton1Click:Connect(function()
                        if setclipboard then
                            pcall(setclipboard, v.id)
                            mostrarAviso("JobId copiado!", Color3.fromRGB(80, 200, 255), 1.5)
                        else
                            mostrarAviso(string.sub(v.id, 1, 24) .. "...", Color3.fromRGB(255,255,255), 2.5)
                        end
                    end)

                    local joinBtn = Instance.new("TextButton")
                    joinBtn.Size = UDim2.new(0, 85, 0, 35)
                    joinBtn.Position = UDim2.new(1, -93, 0.5, -17)
                    joinBtn.BackgroundColor3 = Color3.fromRGB(50, 130, 245)
                    joinBtn.Text = "ENTRAR"
                    joinBtn.TextColor3 = Color3.fromRGB(255,255,255)
                    joinBtn.Font = Enum.Font.GothamBold
                    joinBtn.TextSize = 11
                    joinBtn.Parent = card
                    Instance.new("UICorner", joinBtn).CornerRadius = UDim.new(0,6)
                    joinBtn.MouseButton1Click:Connect(function()
                        mostrarAviso("Teleportando...", Color3.fromRGB(50, 255, 100))
                        pcall(function() TeleportService:TeleportToPlaceInstance(placeId, v.id, player) end)
                    end)
                end
            end
            browserSubHeader.Text = count .. " servidores encontrados"
        else
            browserSubHeader.Text = "API bloqueada — tente novamente."
        end
    end)
end
refreshBtn.MouseButton1Click:Connect(carregarNavegador)

local navegadorAtivo = false
toggleBtn.MouseButton1Click:Connect(function()
    navegadorAtivo = not navegadorAtivo
    if navegadorAtivo then
        toggleBtn.BackgroundColor3 = Color3.fromRGB(130, 60, 230)
        toggleCircle.Position = UDim2.new(1, -21, 0.5, -9)
    
