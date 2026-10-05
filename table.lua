-- DRAPLINE CE table v2.1. Compatible with the v2 game bridge.
if drapCE and drapCE.stop then drapCE.stop() end
if drapCE and drapCE.portable then drapCE.portable.dispose() end
local D = { runtime = __RUNTIME__, active = false, state = {}, queue = {}, records = {}, editors = {}, seq = 0 }
drapCE = D
local list = getAddressList()
local function path(name) return D.runtime and (D.runtime .. '\\' .. name) end
local function readfile(name)
  if not D.runtime then return nil end
  if D.portable then return D.portable.read(path(name)) end
  local f = io.open(path(name), 'rb')
  if not f then return nil end
  local text = f:read('*a'); f:close(); return text
end
local function writefile(name, text)
  if not D.runtime then return false,'请先选择游戏。' end
  if D.portable then return D.portable.write(path(name),text) end
  local target = path(name)
  local temporary = target .. '.ce.tmp'
  local f, err = io.open(temporary, 'wb')
  if not f then return false, err end
  local ok, reason = f:write(text); f:close()
  if not ok then return false, reason end
  os.remove(target)
  return os.rename(temporary, target)
end
local function refresh()
  local raw = readfile('status.tsv')
  if not raw then return false end
  local state = {}
  for line in raw:gmatch('[^\r\n]+') do
    local key, value = line:match('^([^\t]+)\t(.*)$')
    if key then state[key] = tonumber(value) or value end
  end
  if state.protocol ~= 1 then return false end
  if type(state.time) ~= 'number' or math.abs(os.time() * 1000 - state.time) > 5000 then return false end
  if D.lastTime ~= state.time then D.lastTime = state.time; D.seen = getTickCount() end
  if D.server and D.server ~= state.server then
    D.queue = {}; D.pending = nil
    for _, item in pairs(D.records) do pcall(function() item.record.disableWithoutExecute() end) end
    if D.active then table.insert(D.queue, {op='clear',key='_',value=0}) end
  end
  D.server = state.server; D.state = state
  D.inventory = {}
  for id, count in tostring(state.items or ''):gmatch('(%d+):(%d+)') do D.inventory[tonumber(id)] = tonumber(count) end
  for _, key in ipairs({'skill_owned','skill_equipped','skill_granted'}) do
    D[key] = {}
    for id in tostring(state[key] or ''):gmatch('%d+') do D[key][tonumber(id)] = true end
  end
  return D.seen and getTickCount() - D.seen < 3000
end
local function live()
  return D.active and D.seen and getTickCount() - D.seen < 3000 and D.state.ready == 1
end
function D.enqueue(op, key, value)
  if not D.active then return false, '请先勾选“启用连接”。' end
  refresh()
  if op ~= 'clear' and op ~= 'unlock' and not live() then
    return false, '尚未连接到可修改的游戏。请重启已安装桥接模块的游戏，并进入龙娘在队伍中的存档。'
  end
  if #D.queue >= 30 then return false, '命令队列忙，请稍后再试。' end
  table.insert(D.queue, {op=op,key=key,value=value or 0})
  return true
end
function D.poll()
  local fresh = refresh()
  for _, editor in pairs(D.editors) do editor.update() end
  if not D.active then return end
  local ok = writefile('heartbeat.txt', D.client)
  if not ok then return end
  if D.pending and fresh and D.state.client == D.client and D.state.seq == D.pending.seq then
    local request = D.pending; D.pending = nil
    if D.state.error and D.state.error ~= '' then
      local item = D.records[request.key]
      if item and request.op == 'lock' then item.record.disableWithoutExecute() end
      showMessage('游戏未接受修改：' .. D.state.error)
    end
  end
  if D.pending and getTickCount() - D.pending.sent > 4000 then
    D.queue = {}; D.pending = nil
    for _, item in pairs(D.records) do pcall(function() item.record.disableWithoutExecute() end) end
    showMessage('游戏桥接响应超时。请确认游戏已重启、桥接模块已安装，且只有一个游戏实例运行。')
  end
  if not D.pending and #D.queue > 0 and fresh then
    local request = table.remove(D.queue, 1)
    D.seq = D.seq + 1; request.seq = D.seq; request.sent = getTickCount()
    local value = string.format('%.0f', request.value)
    local written = writefile('request.tsv', table.concat({D.client,tostring(request.seq),request.op,request.key,value}, '\t') .. '\n')
    if written then D.pending = request end
  end
end
function D.start()
  if D.active then return end
  if not refresh() then
    if D.portable then D.portable.connect(); return end
    error('未找到运行中的游戏桥接。先运行 Install.ps1 安装，再重启游戏。')
  end
  D.client = tostring(os.time()) .. '_' .. tostring(getTickCount())
  D.active = true; D.queue = {}; D.pending = nil; D.seq = 0
  local ok, err = writefile('heartbeat.txt', D.client)
  if not ok then D.active = false; error('无法写入桥接目录：' .. tostring(err)) end
  D.enqueue('clear','_',0)
  D.timer = createTimer(nil, false); D.timer.Interval = 250; D.timer.OnTimer = D.poll; D.timer.Enabled = true
  D.poll()
end
function D.stop()
  if D.timer then D.timer.destroy(); D.timer = nil end
  if D.active then
    D.seq = D.seq + 1
    writefile('request.tsv', table.concat({D.client,tostring(D.seq),'clear','_','0'}, '\t') .. '\n')
    writefile('heartbeat.txt', '')
  end
  D.active = false; D.queue = {}; D.pending = nil
  local connection=list.getMemoryRecordByID(10)
  if connection then pcall(function() connection.disableWithoutExecute() end) end
  for _, editor in pairs(D.editors) do pcall(function() editor.form.destroy() end) end
  D.editors = {}
  for _, item in pairs(D.records) do pcall(function() item.record.disableWithoutExecute() end) end
end
function D.lock(key, enabled)
  local value = key == 'full_hp' and 1 or D.state[key]
  if enabled and type(value) ~= 'number' then error('当前数值尚未读取。') end
  local ok, err = D.enqueue(enabled and 'lock' or 'unlock', key, value)
  if not ok then error(err) end
end
function D.heal()
  local ok, err = D.enqueue('set','heal',0)
  if not ok then error(err) end
end
__CATALOGUE__
function D.openEditor(kind)
  refresh()
  if not live() then showMessage('请先勾选启用连接，并进入龙娘在队伍中的游戏存档。'); return end
  if (D.state.bridge_version or 1) < 2 then
    showMessage('当前运行的游戏还是旧桥接模块。v2 模块已安装，请正常保存、退出游戏并重启后使用道具/技能编辑。'); return
  end
  if D.editors[kind] then D.editors[kind].form.show(); D.editors[kind].form.bringToFront(); return end
  local isItem = kind == 'items'
  local editor = { mode=kind, rows={}, selectedId=nil }
  local form = createForm(false); editor.form = form
  form.Caption = isItem and 'DRAPLINE 道具数量编辑器' or 'DRAPLINE 技能拥有状态编辑器'
  form.Width = 870; form.Height = 670; form.BorderStyle='bsSingle'
  form.Font.Name = 'Microsoft YaHei UI'; form.Font.Size = 10
  local function control(factory, x, y, w, h)
    local value = factory(form); value.Parent=form; value.Left=x; value.Top=y; value.Width=w; value.Height=h
    return value
  end
  local searchLabel = control(createLabel,16,16,80,24); searchLabel.Caption='搜索名称/ID'
  local search = control(createEdit,110,12,310,28)
  local filter = control(createComboBox,432,12,255,28); filter.Style='csDropDownList'
  local choices = isItem and {'全部道具（常规＋神器）','常规道具','神器 / 重要道具','隐藏道具 / 图鉴','全部数据库（高级）'} or {'可学习技能（战斗＋被动）','战斗技能','被动技能','全部（高级）'}
  for _, caption in ipairs(choices) do filter.Items.add(caption) end
  filter.ItemIndex=0
  local ownedOnly = control(createCheckBox,700,12,140,28); ownedOnly.Caption=isItem and '仅显示持有' or '仅显示拥有'
  editor.search=search; editor.filter=filter; editor.ownedOnly=ownedOnly
  local summary = control(createLabel,16,48,820,28); summary.AutoSize=false
  local view = control(createListView,16,82,822,386); editor.view=view
  view.ViewStyle='vsReport'; view.ReadOnly=true; view.RowSelect=true; view.HideSelection=false
  for _, column in ipairs({{'ID',65},{'中文名称',310},{'类别',140},{isItem and '数量' or '拥有',100},{isItem and '数量上限' or '装备/来源',190}}) do
    local c=view.Columns.add(); c.Caption=column[1]; c.Width=column[2]
  end
  local details = control(createLabel,16,478,820,82); details.AutoSize=false; details.WordWrap=true
  local primary, secondary, quantity
  if isItem then
    local quantityLabel=control(createLabel,16,578,70,28); quantityLabel.Caption='目标数量'
    quantity=control(createEdit,90,572,100,30); quantity.Text='1'
    primary=control(createButton,208,570,150,34); primary.Caption='设置数量'
    secondary=control(createButton,372,570,170,34); secondary.Caption='设为 0（移除）'
  else
    primary=control(createButton,16,570,180,34); primary.Caption='学会选中技能'
    secondary=control(createButton,210,570,180,34); secondary.Caption='忘记选中技能'
  end
  local close=control(createButton,738,570,100,34); close.Caption='关闭'; close.OnClick=function() form.hide() end
  local function owned(entry)
    return isItem and ((D.inventory or {})[entry.id] or 0)>0 or (not isItem and (D.skill_owned or {})[entry.id]==true)
  end
  local function category(entry)
    if isItem then return ({'常规道具','神器 / 重要道具','隐藏道具 / 图鉴','隐藏道具 / 图鉴'})[entry.category] or '其他' end
    if not entry.regular then return '其他（高级）' end
    return entry.category==2 and '被动技能' or '战斗技能'
  end
  local function stateColumns(entry)
    if not live() then return '--','--' end
    if isItem then return tostring((D.inventory or {})[entry.id] or 0),tostring(D.state.item_max or 99) end
    local state=(D.skill_owned or {})[entry.id] and '已拥有' or '未拥有'
    local source=(D.skill_equipped or {})[entry.id] and '已装备' or ((D.skill_granted or {})[entry.id] and '装备/状态授予' or (entry.category==2 and '被动（无需装备）' or '未装备'))
    return state, source
  end
  local function selected() return editor.rows[view.ItemIndex+1] end
  local function rebuild()
    local entry=selected(); local selectedId=entry and entry.id
    local text=search.Text:match('^%s*(.-)%s*$'):lower(); local choice=filter.ItemIndex
    editor.rows={}; view.beginUpdate(); view.Items.clear()
    for _, row in ipairs(D.catalogue[kind]) do
      local pass
      if isItem then
        -- Searching includes every category so a selected filter cannot hide an item.
        pass=(text~='' or choice==4 or (row.regular and
          ((choice==0 and row.category<=2) or (choice==1 and row.category==1) or
           (choice==2 and row.category==2) or (choice==3 and row.category>=3))))
      else pass=(choice==3 or (row.regular and (choice==0 or row.category==choice))) end
      if pass and (not ownedOnly.Checked or owned(row)) and
        (text=='' or row.name:lower():find(text,1,true) or tostring(row.id)==text) then
        editor.rows[#editor.rows+1]=row
        local item=view.Items.add(); item.Caption=tostring(row.id)
        item.SubItems.add(row.name); item.SubItems.add(category(row))
        local value,source=stateColumns(row); item.SubItems.add(value); item.SubItems.add(source)
      end
    end
    view.endUpdate()
    view.ItemIndex=-1
    for index,row in ipairs(editor.rows) do if row.id==selectedId then view.ItemIndex=index-1; break end end
    if view.ItemIndex<0 and #editor.rows>0 then view.ItemIndex=0 end
    editor.update()
  end
  function editor.update()
    if not form.Visible then return end
    local ownedCache=isItem and D.state.items or D.state.skill_owned
    if ownedOnly.Checked and editor.ownedCache~=ownedCache then
      editor.ownedCache=ownedCache; rebuild(); return
    end
    local ready=live(); local entry=selected()
    local writable=ready and (isItem or D.state.scene~='Scene_Battle')
    primary.Enabled=writable and entry~=nil; secondary.Enabled=writable and entry~=nil
    summary.Caption=(ready and ('已连接：'..tostring(D.state.actor or '龙娘')) or '连接已断开')..' | '..#editor.rows..' 项 | '..(isItem and '名称/ID 搜索全部分类；数量 0 移除' or '学会后在游戏内装备战斗技能；技能只在非战斗状态编辑')
    for index,row in ipairs(editor.rows) do
      local value,source=stateColumns(row); local item=view.Items[index-1]
      item.SubItems[2]=value; item.SubItems[3]=source
    end
    if entry then
      local value,source=stateColumns(entry)
      details.Caption='ID '..entry.id..'：'..entry.name..' | '..category(entry)..' | '..value..' | '..source..'\n'..entry.description
      if quantity and editor.selectedId~=entry.id then quantity.Text=tostring((D.inventory or {})[entry.id] or 1) end
      editor.selectedId=entry.id
    else details.Caption='当前筛选没有匹配项。'; editor.selectedId=nil end
  end
  local function submit(value)
    local entry=selected(); if not entry then return end
    local ok,err=D.enqueue('set',(isItem and 'item_' or 'skill_')..entry.id,value)
    if not ok then showMessage(err) else summary.Caption='已提交：'..entry.name..'，等待游戏应答。' end
  end
  primary.OnClick=function()
    if not isItem then submit(1); return end
    local value=tonumber(quantity.Text)
    if not value or value~=math.floor(value) or value<0 or value>(D.state.item_max or 99) then
      showMessage('请输入 0 到 '..tostring(D.state.item_max or 99)..' 之间的整数。'); return
    end
    submit(value)
  end
  secondary.OnClick=function() submit(0) end
  editor.primary=primary; editor.secondary=secondary; editor.quantity=quantity
  view.OnClick=editor.update
  search.OnChange=rebuild; filter.OnChange=rebuild; ownedOnly.OnChange=rebuild
  D.editors[kind]=editor
  form.OnShow=function() editor.update() end
  form.fixDPI(); form.centerScreen(); form.show(); rebuild()
end
local oldValueChange = list.OnValueChange
list.OnValueChange = function(sender, record)
  local item = D.records[record.ID]
  if not item then
    if oldValueChange then return oldValueChange(sender, record) end
    return false
  end
  if not live() then showMessage('请先启用连接并进入游戏存档。'); return true end
  if not item.editable then return true end
  local text = inputQuery(record.Description, item.hint .. '\n输入整数；勾选此行可锁定当前数值。', tostring(D.state[item.key] or 0))
  if text then
    local value = tonumber(text)
    if not value or value ~= math.floor(value) or math.abs(value) > 1000000000 then
      showMessage('请输入范围内的整数。'); return true
    end
    local ok, err = D.enqueue('set',item.key,value)
    if not ok then showMessage(err) end
  end
  return true
end
__BINDINGS__
local root = list.getMemoryRecordByID(1)
if root then root.OnDestroy = function()
  D.stop()
  list.OnValueChange = oldValueChange
end end
