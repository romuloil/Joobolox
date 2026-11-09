use std::{fs::File,io::{BufReader,BufWriter}};
use rbx_dom_weak::{WeakDom,InstanceBuilder};
use rbx_types::{Ref,Variant};
use serde_json::json;
fn walk(dom:&WeakDom, r:Ref,out:&mut Vec<Ref>){out.push(r);for c in dom.get_by_ref(r).unwrap().children(){walk(dom,*c,out)}}
fn main() {
 let args:Vec<String>=std::env::args().collect();
 let dom=rbx_binary::from_reader(BufReader::new(File::open(&args[1]).unwrap())).unwrap();
 let mut all=Vec::new();walk(&dom,dom.root_ref(),&mut all);
 if args.get(2).map(|s|s.as_str())==Some("--verify") { println!("Independent binary decode: {} instances",all.len()-1); return; }
 let root=*all.iter().find(|r| {let i=dom.get_by_ref(**r).unwrap();i.name=="Dealership" && i.class.as_str()=="Model" && i.children().iter().any(|c|dom.get_by_ref(*c).unwrap().name=="ParkingLot")}).unwrap();
 let mut selected=Vec::new();walk(&dom,root,&mut selected);
 let mut out=WeakDom::new(InstanceBuilder::new("DataModel"));
 let cloned=dom.clone_into_external(root,&mut out);
 out.transfer_within(cloned,out.root_ref());
 out.get_by_ref_mut(cloned).unwrap().name="DealershipTemplate".into();
 let mut nodes=Vec::new();walk(&out,cloned,&mut nodes);
 let mut removed=Vec::new();
 for r in nodes {
  let Some(i)=out.get_by_ref(r) else {continue};
  if matches!(i.class.as_str(),"Script"|"LocalScript"|"ModuleScript"|"ProximityPrompt"|"ClickDetector"|"TouchTransmitter") {
   removed.push(i.name.clone());out.destroy(r);
  } else if i.properties.contains_key(&"CFrame".into()) && i.properties.contains_key(&"Size".into()) {
   out.get_by_ref_mut(r).unwrap().properties.insert("Anchored".into(),Variant::Bool(true));
  }
 }
 let mut nodes=Vec::new();walk(&out,cloned,&mut nodes);
 let dump:Vec<_>=nodes.iter().map(|r| {
  let i=out.get_by_ref(*r).unwrap();
  let props:serde_json::Map<String,serde_json::Value>=i.properties.iter().filter(|(k,_)|matches!(k.as_str(),"CFrame"|"Size"|"Color"|"Color3uint8"|"Transparency"|"MeshId"|"TextureID"|"Text"|"CanCollide"|"Anchored")).map(|(k,v)|(k.to_string(),serde_json::to_value(v).unwrap())).collect();
  json!({"id":r.to_string(),"parent":i.parent().to_string(),"name":i.name,"class":i.class.as_str(),"props":props})
 }).collect();
 serde_json::to_writer(BufWriter::new(File::create(format!("{}.json",args[2])).unwrap()),&json!({"nodes":dump,"removed":removed})).unwrap();
 rbx_binary::to_writer(BufWriter::new(File::create(&args[2]).unwrap()),&out,&[cloned]).unwrap();
 println!("Extracted {} instances; removed {:?}",nodes.len(),removed);
}
