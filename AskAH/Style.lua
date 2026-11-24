-- Style.lua
-- One look for every AskAH window: the dark panel the deals and sales
-- windows use, a title bar with the name in gold, and a close button.
local _, ns = ...
local S = {}
ns.Style = S

S.BLUE, S.GOLD, S.GREY, S.GREEN, S.RED = "|cff33ccff", "|cffffd200", "|cff999999", "|cff33ff33", "|cffff4040"

local function Tex(parent, layer, r, g, b, a)
  local t = parent:CreateTexture(nil, layer)
  t:SetColorTexture(r, g, b, a)
  return t
end

-- Template to pass to CreateFrame for a skinned window.
function S.Template()
  return BackdropTemplateMixin and "BackdropTemplate" or nil
end

-- Dark panel, title bar (barH tall), gold title, close button.
-- Returns the title font string.
function S.Skin(f, titleText, barH)
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
    Tex(f, "BACKGROUND", 0.05, 0.05, 0.07, 0.95):SetAllPoints()
  end
  local bar = Tex(f, "BORDER", 1, 1, 1, 0.06)
  bar:SetPoint("TOPLEFT", 4, -4); bar:SetPoint("TOPRIGHT", -4, -4); bar:SetHeight(barH - 4)
  local div = Tex(f, "BORDER", 1, 1, 1, 0.15)
  div:SetPoint("TOPLEFT", 4, -barH); div:SetPoint("TOPRIGHT", -4, -barH); div:SetHeight(1)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 14, -10)
  title:SetJustifyH("LEFT")
  title:SetText(titleText or "")
  f.title = title

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)
  f.closeButton = close
  return title
end
