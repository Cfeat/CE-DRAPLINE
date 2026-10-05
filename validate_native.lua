-- Run in a separate CE with DRAPLINE_CE_NATIVE_FIXTURE pointing to a Python test fixture.
local fixture=os.getenv('DRAPLINE_CE_NATIVE_FIXTURE')
if not fixture or fixture=='' then return end
local tablePath=os.getenv('DRAPLINE_CE_NATIVE_TABLE')
local output=fixture..'\\native-result.txt'
local function textFile(filename)
  local stream=createMemoryStream(); assert(stream.loadFromFileNoError(filename)); stream.Position=0
  local text=stream.readString(stream.Size); stream.destroy(); return text
end
local function report(text)
  local stream=createFileStream(output,0xff00 | 0x0040); stream.writeString(text); stream.destroy()
end
local failed=false
local function guarded(callback)
  return function(...)
    if failed then return end
    local args={...}; local ok,err=xpcall(function() callback(table.unpack(args)) end,debug.traceback)
    if not ok then failed=true; report('FAIL '..err) end
  end
end
createTimer(500,guarded(function()
  DRAPLINE_CE_TEST=true
  getTempFolder=function() return fixture..'\\Unicode 临时 scripts' end
  showMessage=function(message) failed=true; report('FAIL unexpected dialog: '..tostring(message)) end
  report('RUN loading actual CT')
  -- CE Share's startup wrapper may try to log out before its server is configured.
  -- Suppress account/network activity only in this isolated verification process.
  local clearCredentials=ceshare and ceshare.ClearCredentials
  if clearCredentials then ceshare.ClearCredentials=function() end end
  local stream=createMemoryStream(); assert(stream.loadFromFileNoError(tablePath)); loadTable(stream,false,true); stream.destroy()
  if clearCredentials then ceshare.ClearCredentials=clearCredentials end
  local D=assert(drapCE); local P=assert(D.portable)
  P.tempRoot=fixture; P.exe=textFile(fixture..'\\fixture-path.txt')..'\\DRAPLINE.exe'
  report('RUN native setup job')
  P.job('install',guarded(function(values)
    assert(values.status=='installed',values.message)
    assert(fileExists(P.exe:match('^(.*)[\\/]')..'\\resources\\app\\electron\\drapline-ce\\renderer.js'))
    local runtime=values.runtime
    local client,seq='',0
    local count,learned=2,false
    local function publish()
      local raw=P.read(runtime..'\\request.tsv')
      if raw then
        local fields={}; for value in raw:gmatch('[^\t\r\n]+') do fields[#fields+1]=value end
        if #fields==5 then
          client=fields[1]; seq=tonumber(fields[2])
          if fields[4]=='item_170' then count=tonumber(fields[5]) end
          if fields[4]=='skill_121' then learned=fields[5]=='1' end
        end
      end
    local state='protocol\t1\npid\t'..getCheatEngineProcessID()..'\ntime\t'..(os.time()*1000)..'\nserver\tnative-test\nbridge_version\t2\nready\t1\nscene\tScene_Map\nactor\tfixture\nitem_max\t99\nitems\t21:7,170:'..count..'\nskill_owned\t'..(learned and '121' or '')..'\nskill_equipped\t\nclient\t'..client..'\nseq\t'..seq..'\nerror\t\n'
      assert(P.write(runtime..'\\status.tsv',state))
    end
    publish()
    local server=createTimer(nil,false); server.Interval=100; server.OnTimer=guarded(publish); server.Enabled=true
    P.connect()
    local timer=createTimer(nil,false); timer.Interval=300; local stage=0; local started=getTickCount(); local failureProcess; local ticks=0
    timer.OnTimer=guarded(function()
      assert(getTickCount()-started<45000,'Native verification timed out at stage '..stage)
      if stage==0 and D.active then
        assert(getAddressList().getMemoryRecordByID(10).Active,'Connection record must activate automatically')
        D.openEditor('items'); local editor=D.editors.items
        assert(#editor.rows==120,'Default item list changed')
        editor.filter.ItemIndex=2; editor.filter.OnChange(); assert(#editor.rows==78)
        editor.filter.ItemIndex=1; editor.filter.OnChange()
        editor.search.Text='王冠'; editor.search.OnChange()
        assert(#editor.rows==1 and editor.rows[1].id==170,'Global Chinese search failed')
        publish(); editor.quantity.Text='8'; editor.primary.OnClick(); stage=1
        report('RUN Unicode transport and inventory write')
      elseif stage==1 and count==8 and D.inventory[170]==8 then
        D.openEditor('skills'); local editor=D.editors.skills
        editor.search.Text='121'; editor.search.OnChange(); assert(#editor.rows==1)
        publish(); editor.primary.OnClick(); stage=2; report('RUN skill ownership write')
      elseif stage==2 and learned and D.skill_owned[121] then
        D.editors.skills.secondary.OnClick(); stage=3
      elseif stage==3 and not learned and not D.skill_owned[121] then
        D.stop(); P.dispose()
        assert(not getAddressList().getMemoryRecordByID(10).Active)
        DRAPLINE_CE_TEST=nil
        if clearCredentials then ceshare.ClearCredentials=function() end end
        local stream=createMemoryStream(); assert(stream.loadFromFileNoError(tablePath)); loadTable(stream,false,true); stream.destroy()
        if clearCredentials then ceshare.ClearCredentials=clearCredentials end
        D=assert(drapCE); D.portable.tempRoot=fixture
        stage=4; report('RUN CT reopen and automatic startup')
      elseif stage==4 and D.active then
        assert(getAddressList().getMemoryRecordByID(10).Active)
        assert(D.inventory[170]==8 and not D.skill_owned[121])
        server.destroy(); D.stop()
        local dialog=createOpenDialog(nil); dialog.Title='选择游戏'; dialog.Filter='DRAPLINE.exe|DRAPLINE.exe'
        dialog.Options='[ofFileMustExist,ofPathMustExist,ofNoChangeDir]'; dialog.destroy()
        failureProcess=D.portable.launchPowerShell("Start-Sleep -Milliseconds 600; throw '中文错误测试'")
        stage=5; report('RUN background error reporting and GUI responsiveness')
      elseif stage==5 then
        ticks=ticks+1
        if failureProcess.done then
          assert(ticks>=2,'CE timer blocked during PowerShell worker')
          assert(failureProcess.exitCode==1,failureProcess.exitCode)
          assert(failureProcess.output:find('中文错误测试',1,true),failureProcess.output)
          timer.destroy(); D.portable.dispose()
          report('PASS native CE: actual CT load/reopen and automatic startup; embedded PowerShell job; Unicode paths and streams; automatic connection/record activation; 120 items including all 78 artifacts; cross-category Chinese search; inventory and learn/forget round trips; native file-dialog configuration; background errors and responsive GUI; stop cleanup. No live game connection or save changes.')
        end
      end
    end)
    timer.Enabled=true
  end))
end))
