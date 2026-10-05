-- Embedded setup controller. Only the finished CT is needed on the other PC.
do
  local P={message='正在查找游戏…',disposed=false}; D.portable=P
  local temporary=getTempFolder():gsub('[\\/]+$','')
  local prefix=temporary..'\\DRAPLINE-CE-single-'..os.time()..'-'..getTickCount()..'-'..math.random(100000,999999)
  local script=prefix..'.ps1'
  local cache=temporary..'\\DRAPLINE-CE-single-game.txt'
  function P.read(filename)
    if not filename then return nil end
    local stream=createMemoryStream()
    local ok=stream.loadFromFileNoError(filename)
    local text
    if ok and stream.Size<=524288 then stream.Position=0; text=stream.readString(stream.Size) end
    stream.destroy(); return text
  end
  function P.write(filename,text)
    local ok,reason=pcall(function()
      local stream=createFileStream(filename,0xff00 | 0x0040)
      local written,err=pcall(function() stream.writeString(text) end)
      stream.destroy(); if not written then error(err) end
    end)
    return ok,reason
  end
  local function parse(text)
    local values={}
    for line in text:gmatch('[^\r\n]+') do local key,value=line:match('^([^\t]+)\t(.*)$'); if key then values[key]=value end end
    return values
  end
  local function jsonString(text)
    return '"'..tostring(text or ''):gsub('[%z\1-\31\\"]',function(c)
      if c=='\\' then return '\\\\' end
      if c=='"' then return '\\"' end
      return string.format('\\u%04x',c:byte())
    end)..'"'
  end
  local function notice(message)
    P.message=message
    showMessage(message)
  end
  local function psString(text) return "'"..text:gsub("'","''").."'" end
  function P.launchPowerShell(code)
    -- Run in a worker: CE stays responsive and PowerShell failures are observable.
    -- runCommand takes an argument array and supports Unicode, unlike shellExecute.
    local powershell=(os.getenv('SystemRoot') or [[C:\Windows]])..[[\System32\WindowsPowerShell\v1.0\powershell.exe]]
    P.launchSerial=(P.launchSerial or 0)+1
    local launchScript=prefix..'.launch'..P.launchSerial..'.ps1'
    local written,reason=P.write(launchScript,'\239\187\191$ErrorActionPreference = "Stop"\n[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)\ntry {\n'..code..'\n} catch { Write-Output $_.Exception.Message; exit 1 }')
    if not written then return {done=true,exitCode=-1,output=tostring(reason)} end
    local arguments={'-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',launchScript}
    local process={done=false}
    createThread(function()
      local ok,output,exitCode=pcall(runCommand,powershell,arguments)
      process.output=tostring(output or ''); process.exitCode=ok and exitCode or -1
      process.done=true
    end)
    return process
  end
  function P.job(mode,callback)
    if P.busy then P.message='正在处理上一个操作，请稍候。'; return false end
    if P.disposed then return false end
    if type(runCommand)~='function' or type(createThread)~='function' then
      notice('此 CE 缺少后台设置接口。请使用 Windows 64 位 Cheat Engine 7.5 或更新版本。'); return false
    end
    local config=prefix..'.request'; local result=prefix..'.result'
    P.serial=(P.serial or 0)+1; result=result..P.serial
    local text='{"mode":'..jsonString(mode)..',"exe":'..jsonString(P.exe)..',"result":'..jsonString(result)..',"tempRoot":'..jsonString(P.tempRoot)..'}'
    local ok,err=P.write(script,'\239\187\191'..__SETUP_SCRIPT__)
    if ok then ok,err=P.write(config,text) end
    if not ok then notice('无法写入临时设置文件：'..tostring(err)); return false end
    P.busy=true; P.message=(mode=='install' and '正在校验游戏并安装/备份…' or mode=='uninstall' and '正在校验并卸载…' or '正在查找游戏桥接…')
    local timer=createTimer(nil,false); P.jobTimer=timer; timer.Interval=200
    local started=getTickCount()
    local process=P.launchPowerShell('& '..psString(script)..' -Request '..psString(config))
    timer.OnTimer=function()
      local response=P.read(result)
      if response then
        timer.destroy(); P.jobTimer=nil; P.busy=false
        local values=parse(response); P.message=values.message or '设置完成。'
        if P.disposed then return end
        if values.status=='error' then notice(P.message); return end
        callback(values)
      elseif process.done then
        timer.destroy(); P.jobTimer=nil; P.busy=false
        notice('设置进程未生成结果（退出码 '..tostring(process.exitCode)..'）。\n'..process.output:sub(1,2000))
      elseif getTickCount()-started>120000 then
        timer.destroy(); P.jobTimer=nil; P.busy=false
        notice('设置进程未返回。请检查游戏目录写权限与 Windows PowerShell；不要重复安装，先确认后台操作已结束。')
      end
    end
    timer.Enabled=true; return true
  end
  local function attach(values)
    if values.exe and values.exe~='' then P.exe=values.exe; P.write(cache,P.exe) end
    D.runtime=values.runtime; D.lastTime=nil; D.seen=nil; D.server=nil
    D.start()
    local record=list.getMemoryRecordByID(10)
    if record then record.Active=true end
    P.message='已连接。'
  end
  local function installed(values)
    if values.status=='connected' then attach(values); return end
    if values.status~='installed' then notice(values.message or '尚未连接。'); return end
    P.exe=values.exe; P.write(cache,P.exe); D.runtime=values.runtime
    P.message='正在启动游戏并等待连接…'
    local directory=P.exe:match('^(.*)[\\/]')
    local process=P.launchPowerShell('$ErrorActionPreference = "Stop"; Start-Process -FilePath '..psString(P.exe)..' -WorkingDirectory '..psString(directory)..' -WindowStyle Normal')
    P.job('wait',function(result)
      if result.status=='connected' then attach(result)
      elseif process.done and process.exitCode~=0 then notice('桥接已安装，但游戏未能启动：\n'..process.output:sub(1,2000))
      else notice('桥接已安装。请启动游戏，然后点击“一键连接 / 首次安装”。') end
    end)
  end
  function P.select()
    if P.busy then return end
    local dialog=createOpenDialog(nil)
    dialog.Title='选择 DRAPLINE.exe（首次安装前请先保存并退出游戏）'
    dialog.Filter='DRAPLINE.exe|DRAPLINE.exe'; dialog.Options='[ofFileMustExist,ofPathMustExist,ofNoChangeDir]'
    if P.exe and P.exe~='' then dialog.InitialDir=P.exe:match('^(.*)[\\/]') end
    local accepted=dialog.execute(); local selected=dialog.FileName; dialog.destroy()
    if not accepted then P.message='未选择游戏；可点击“一键连接 / 首次安装”重试。'; return end
    D.stop(); P.exe=selected; D.runtime=nil
    P.job('install',installed)
  end
  function P.connect()
    if P.busy then return end
    P.job('probe',function(values)
      if values.status=='connected' then attach(values)
      elseif P.exe and P.exe~='' then P.job('install',installed)
      else P.select() end
    end)
  end
  function P.uninstall()
    if P.busy then return end
    if not P.exe or P.exe=='' then
      notice('请先通过“选择或切换游戏”指定游戏。卸载前需在游戏内保存并正常退出。'); return
    end
    D.stop()
    P.job('uninstall',function(values) D.runtime=nil; notice(values.message) end)
  end
  function P.dispose()
    P.disposed=true
    if P.jobTimer then P.jobTimer.destroy(); P.jobTimer=nil end
  end
  P.exe=P.read(cache)
  local status=list.getMemoryRecordByID(11)
  if status then
    local previous=status.OnGetDisplayValue
    status.OnGetDisplayValue=function(...)
      if not D.active then return true,P.message end
      return previous(...)
    end
  end
  local root=list.getMemoryRecordByID(1)
  if root then
    local previous=root.OnDestroy
    root.OnDestroy=function(...) P.dispose(); if previous then return previous(...) end end
  end
  if not DRAPLINE_CE_TEST then createTimer(250,function() if not P.disposed then P.connect() end end) end
end
