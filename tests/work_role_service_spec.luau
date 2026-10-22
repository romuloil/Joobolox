return function(mockSource,fixtureSource,configSource,rulesSource,serviceSource)
 local count=0;local function check(value,message)count+=1;assert(value,message)end
 local makeFixture=assert(loadstring(fixtureSource))()
 local function fixture(r6)
  local f=makeFixture(mockSource);local m=f.mock;local p=f.player(1,r6)
  m.load('GameConfig',"return {Remotes={UIUpdate='UIUpdate'}}")
  m.load('WorkRoleConfig',configSource);m.load('WorkRoleRules',rulesSource)
  local service=m.load('WorkRoleService',serviceSource,true)
  local messages={};local sites={}
  for i,role in ipairs({'Policial','Taxista','Pizzaiolo','Atendente','Entregador'})do sites[role]={uniformPrompts={f.prompt((i-1)*30)}}end
  service.init({UIUpdate={FireClient=function(_,_,kind,data)table.insert(messages,{kind=kind,data=data})end}},sites)
  local shirt=f.instance('Shirt');shirt.Name='Shirt';shirt.ShirtTemplate='original-shirt';shirt.Parent=p.Character
  local pants=f.instance('Pants');pants.Name='Pants';pants.PantsTemplate='original-pants';pants.Parent=p.Character
  local graphic=f.instance('ShirtGraphic');graphic.Graphic='original-graphic';graphic.Parent=p.Character
  local hat=f.instance('Accessory');hat.AccessoryType=m.Enum.AccessoryType.Hat;hat.Parent=p.Character
  local handle=f.instance('Part');handle.Name='Handle';handle.Transparency=0.25;handle.Parent=hat
  local body=f.instance('BodyColors');body.HeadColor='untouched';body.Parent=p.Character
  f.player1,f.service,f.sites,f.shirt,f.pants,f.graphic,f.hat,f.handle,f.body=p,service,sites,shirt,pants,graphic,hat,handle,body
  return f
 end
 for _,r6 in ipairs({false,true})do
  local f=fixture(r6);local p,s=f.player1,f.service
  p:SetAttribute('WorkRole','Policial');p:SetAttribute('WorkUniformRole','Policial')
  check(not s.hasRole(p,'Policial'),'forged attrs grant no role')
  check(not s.equipUniform(p,'Policial'),'forged attrs grant no uniform')
  local changes={};local connection=s.onChanged(function(_,newRole,oldRole)table.insert(changes,{new=newRole,old=oldRole})end)
  check(s.assign(p,'Policial'),'assign police')
  check(#changes==1 and changes[1].new=='Policial','role listener sees assignment')
  check(s.assign(p,'Policial')and#changes==1,'same assignment is idempotent')
  check(not s.assign(p,'Taxista'),'refuse simultaneous occupation')
  f.move(p,40)
  check(not s.equipUniform(p,'Policial'),'far wardrobe rejected')
  f.move(p,0)
  check(s.equipUniform(p,'Policial'),'local employed uniform succeeds')
  check(f.shirt.ShirtTemplate==''and f.pants.PantsTemplate==''and f.graphic.Graphic=='','old clothing temporarily hidden')
  check(f.handle.Transparency==1,'hat hidden while uniform equipped')
  check(f.body.HeadColor=='untouched','body colors preserved')
  check(p:GetAttribute('WorkUniformRole')=='Policial','uniform role is presented')
  local uniform=p.Character:FindFirstChild('UniformeDeTrabalho')
  check(uniform and uniform:GetAttribute('WorkUniform')==true,'uniform leased model exists')
  local parts=0
  for _,part in ipairs(uniform:GetDescendants())do
   if part:IsA('BasePart')then
    parts+=1;check(not part.CanCollide and not part.CanTouch and part.Massless,'uniform has no movement collision or mass')
   end
  end
  check(parts>=8,'uniform includes clothing and cap pieces')
  check(not s.clear(p,'Taxista')and s.hasRole(p,'Policial'),'stale cleanup cannot remove new role')
  check(s.clear(p,'Policial'),'leave role')
  check(not p.Character:FindFirstChild('UniformeDeTrabalho'),'leased model removed')
  check(f.shirt.ShirtTemplate=='original-shirt'and f.pants.PantsTemplate=='original-pants'and f.graphic.Graphic=='original-graphic','clothing restored exactly')
  check(f.handle.Transparency==0.25,'hat visibility restored exactly')
  check(s.getRole(p)==nil and p:GetAttribute('WorkUniformRole')==nil,'leave clears authoritative and visible state')
  check(#changes==2 and changes[2].old=='Policial','listeners receive leave')
  connection:Disconnect();check(s.assign(p,'Taxista')and#changes==2,'disconnected listener stays disconnected')
  f.move(p,30);f.advance(1)
  check(s.equipUniform(p,'Taxista'),'taxi uniform available only own job')
  local added=f.instance('Shirt');added.ShirtTemplate='late-shirt';added.Parent=p.Character
  check(added.ShirtTemplate=='','late-loaded clothes also hidden')
  added.ShirtTemplate='late-final-template'
  check(added.ShirtTemplate=='','appearance template assigned after parenting stays hidden')
  local jacket=f.instance('Accessory');jacket.AccessoryType=f.mock.Enum.AccessoryType.Jacket;jacket.Parent=p.Character
  local jacketHandle=f.instance('Part');jacketHandle.Name='Handle';jacketHandle.Transparency=0.35;jacketHandle.Parent=jacket
  check(jacketHandle.Transparency==1,'layered jacket cannot cover work uniform')
  p:SetAttribute('Detained',true)
  check(s.getRole(p)==nil and added.ShirtTemplate=='late-final-template','detention clears lease and restores latest loaded clothes')
  check(jacketHandle.Transparency==0.35,'detention restores layered clothing before custody takes over')
 end
 local f=fixture(false);local p,s=f.player1,f.service
 check(s.assign(p,'Policial')and s.equipUniform(p),'setup for death')
 p.Character:FindFirstChildOfClass('Humanoid').Died:Fire()
 check(not p.Character:FindFirstChild('UniformeDeTrabalho')and s.getRole(p)=='Policial','death removes uniform while normal role lifecycle remains caller-owned')
 f.advance(1);check(s.equipUniform(p),'uniform can be reissued')
 local old=p.Character;p.Character=f.character(false);p.CharacterAdded:Fire(p.Character)
 check(not old:FindFirstChild('UniformeDeTrabalho')and s.getRole(p)=='Policial','respawn restores old avatar and keeps normal job role')
 p.Character:FindFirstChild('Head'):Destroy();f.advance(1)
 check(not s.equipUniform(p),'incomplete avatar refuses uniform')
 check(f.shirt.ShirtTemplate=='original-shirt'and not p.Character:FindFirstChild('UniformeDeTrabalho'),'failed build leaves no leased model')
 print('PASS WorkRoleService: '..count..' lifecycle checks (mock services)')
end
