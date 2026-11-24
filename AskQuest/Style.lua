-- Style.lua
-- Same look as AskAH's windows: dark panel, title bar with the name in
-- gold, close button. Also ns.Print so chat lines share one prefix.
local _, ns = ...

function ns.Print(msg) print("|cff33ccffAskQuest|r: " .. msg) end

function ns.WindowTemplate() return BackdropTemplateMixin and "BackdropTemplate" or nil end

function ns.Skin(f, titleText, barH)
  barH = barH or 30
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
    f:SetBackdropBorderColor(0.5, 0.5, 0.55, 1)
  else
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0.05, 0.05, 0.07, 0.95)
    bg:SetAllPoints()
  end
  local bar = f:CreateTexture(nil, "BORDER")
  bar:SetColorTexture(1, 1, 1, 0.06)
  bar:SetPoint("TOPLEFT", 4, -4); bar:SetPoint("TOPRIGHT", -4, -4); bar:SetHeight(barH - 4)
  local div = f:CreateTexture(nil, "BORDER")
  div:SetColorTexture(1, 1, 1, 0.15)
  div:SetPoint("TOPLEFT", 4, -barH); div:SetPoint("TOPRIGHT", -4, -barH); div:SetHeight(1)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 14, -10)
  title:SetPoint("RIGHT", f, "RIGHT", -34, 0)
  title:SetJustifyH("LEFT")
  title:SetWordWrap(false)
  title:SetText(titleText or "")
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)
  f.closeButton = close
  return title
end
