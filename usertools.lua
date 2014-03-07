local G = ...
local ids = {}
local menuID
local tool

-- Some utility functions that offer functionality used by the usertool functions
local function GetMultipleSelections(editor)
  local selections = {}
  for i=0,editor:GetSelections()-1 do
    table.insert(selections, {
      editor:GetSelectionNStart(i),
      editor:GetSelectionNEnd(i)
    })
  end
  -- Sort the selections from last to first, as otherwise
  -- replacing earlier elements changes positions of later ones
  table.sort(selections, function(a, b) return a[1] > b[1] end)
  return selections
end

local function GetMultipleCarets(editor)
  local carets = {}
  for i=0,editor:GetSelections()-1 do
    table.insert(carets, {i, editor:GetSelectionNCaret(i)})
  end
  -- Sort the carets from last to first, as otherwise
  -- inserting text at earlier positions changes positions of later ones
  table.sort(carets, function(a, b) return a[2] > b[2] end)
  return carets
end

local function LinesFromSection(editor, section)
  local startLine = editor:LineFromPosition(section[1])
  local endLine = editor:LineFromPosition(section[2])
  local startPos = editor:PositionFromLine(startLine)
  local endPos = editor:GetLineEndPosition(endLine) + 1
  return {startLine, endLine}, {startPos, endPos}
end

local function ReplaceSection(editor, section, newText, selectionN)
  editor:SetTargetStart(section[1])
  editor:SetTargetEnd(section[2])
  
  editor:ReplaceTarget(newText)
  editor:SetSelection(section[1], section[1] + #newText)
end


-- Calls the function with no arguments so it can do anything it wants
local function Usertool_Generic(usertoolFn)
  usertoolFn()
end

-- Sends content of the selection, replaces with returned result, selects result
local function Usertool_Text_ModifySelection(usertoolFn)
  local editor = ide:GetEditor()
  
  local selections = GetMultipleSelections(editor)
    
  for n, selection in pairs(selections) do
    local text = string.sub(editor:GetText(), selection[1] + 1, selection[2])
    local newText = usertoolFn(text)
    ReplaceSection(editor, selection, newText, n - 1)
  end
end

-- Sends file contents, replaces them with the result if it's not nil
local function Usertool_Text_ModifyFile(usertoolFn)
  local editor = ide:GetEditor()
  
  local newText = usertoolFn(editor:GetText())
  if newText ~= nil then
    editor:SetText(newText)
  end
end

-- Sends lines encompassing the selection, replaces them with returned lines, selects result
local function Usertool_Text_ModifyLines(usertoolFn)
  local editor = ide:GetEditor()
  local selections = GetMultipleSelections(editor)
  for n, selection in pairs(selections) do
    local lineRange, posRange = LinesFromSection(editor, selection)
    local lines = {}
    for i=lineRange[1], lineRange[2] do
      table.insert(lines, editor:GetLine(i))
    end
    
    local newText = ""
    local newLines = usertoolFn(lines)
    for i, line in ipairs(newLines) do
      newText = newText .. line
    end
    
    ReplaceSection(editor, posRange, newText, n - 1)
  end
end

-- Inserts returned value at cursor position
local function Usertool_Text_Insert(usertoolFn)
  local editor = ide:GetEditor()
  local carets = GetMultipleCarets(editor)
  for _, caretNAndPos in ipairs(carets) do
    local n, caret = unpack(caretNAndPos)
    local newText = usertoolFn()
    editor:InsertText(caret, newText)
    -- FIXME: Fix only one of the carets being actually re-careted after insertion
    editor:SetSelectionNCaret(n, caret + #newText)
  end
end

local usertoolFunctions = {
  ["text.modify_selection"] = Usertool_Text_ModifySelection,
  ["text.modify_lines"] = Usertool_Text_ModifyLines,
  ["text.modify_file"] = Usertool_Text_ModifyFile,
  ["text.insert"] = Usertool_Text_Insert,
  ["generic"] = Usertool_Generic,
}

local function RunUsertool(usertoolName)
  local usertool = ide.config.usertools[usertoolName]
  local dispatcher = usertoolFunctions[usertool.tool_type]
  if dispatcher ~= nil then
    dispatcher(usertool.fn)
  else
    local message = usertoolName .. ": " .. usertool.tool_type .. " is not a supported usertool type"
    ReportError(message)
  end
end

local function count(_table)
  local n = 0
  for _, _ in pairs(_table) do
    n = n + 1
  end
  return n
end

return {
  name = "Usertools",
  description = "Allows defining simple usertool functions and their hotkeys in config files",
  author = "Asmageddon",
  version = 0.1,

  onRegister = function(self)
    -- If no usertools are configured, do nothing and return
    if (ide.config.usertools == nil or count(ide.config.usertools) == 0) then
      return
    end
    
    local menuBar = ide:GetMenuBar()
    
    local usertoolsMenu = wx.wxMenu()
    
    local usertools = ide.config.usertools
    table.sort(usertools, function(a,b) return a.tool_type < b.tool_type end)
  
    -- name, description, tool_type, fn
    for name, tool in pairs(ide.config.usertools) do
      local id = G.ID("usertools." .. name)
      local hotkey = KSC(id)
      usertoolsMenu:Append(id, tool.name .. hotkey, tool.description)
      table.insert(ids, id)
      -- Connect the event
      ide:GetMainFrame():Connect(
        id,
        wx.wxEVT_COMMAND_MENU_SELECTED,
        function() RunUsertool(name) end
      )
    end
  
    menuID = menuBar:Append(usertoolsMenu, TR("&Usertools"))
  end,

  onUnRegister = function(self)
    local menuBar = ide:GetMenuBar()
    for _, id in pairs(ids) do
      ide:GetMainFrame():Disconnect(id, wx.wxID_ANY, wx.wxEVT_COMMAND_MENU_SELECTED)
    end
    if menuID then menuBar:Destroy(menuID) end
  end,
}