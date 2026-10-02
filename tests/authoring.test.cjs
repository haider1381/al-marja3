// Run from repository root: node tests/authoring.test.cjs
const fs = require('node:fs');
const assert = require('node:assert/strict');
const source = fs.readFileSync('index.html','utf8').match(/<script>([\s\S]*?)<\/script>/)[1].replace(/\ninit\(\);\s*$/, '');
const nodes = Object.create(null);
function node(id) {
  return nodes[id] || (nodes[id] = {
    value:'', disabled:false, hidden:false, textContent:'', innerHTML:'', files:[], checked:false, options:[],
    classList:{add(){},remove(){}}, appendChild(o){this.options.push(o);}, focus(){},
    reset(){this.resetCount=(this.resetCount||0)+1;}, elements:[]
  });
}
const document = {getElementById:node, createElement:()=>({}), querySelectorAll:()=>[]};
const api = new Function('document','crypto', source + `
return {
 onSubmitLecture, syncAccess,
 setup(c,collection,list,id) {client=c;col=collection;lectures=list;editingId=id;canWrite=true;},
 isSaving(){return savingMaterial;}, currentLectures(){return lectures;}
};`)(document,{randomUUID:()=> 'test-uuid'});
async function run() {
  const fields = {f_title:'Lecture',f_source:'Dr A',f_category:'Medicine',f_topic:'Cardiology',f_type:'ملف PDF',f_link:'',f_text:'',f_notes:''};
  Object.entries(fields).forEach(([id,value])=>{node(id).value=value;});
  const file={name:'lecture.pdf',type:'application/pdf',size:100};
  node('f_pdf').files=[file];
  node('lectureForm').elements=[node('saveBtn'),node('cancelBtn'),node('f_title')];
  let saved;let uploaded;
  api.setup({storage:{from(bucket) {
    assert.equal(bucket,'lecture-files');
    return {async upload(path,actual,options){uploaded={path,actual,options};return {error:null};}};
  }}},{async add(data){saved=data;}},[],null);
  await api.onSubmitLecture({preventDefault(){}});
  assert.equal(saved.filePath,'pdf/test-uuid.pdf');
  assert.equal(uploaded.actual,file);
  assert.equal(uploaded.options.upsert,false);
  assert.equal(api.isSaving(),false);
  assert.ok(node('lectureForm').resetCount);
  const resets=node('lectureForm').resetCount;
  Object.entries(fields).forEach(([id,value])=>{node(id).value=value;});
  node('f_pdf').files=[];
  node('f_text').value='keep this draft';
  api.setup({}, {doc(){return {async update(){throw Error('network');}};}},[{id:'x',filePath:'pdf/old.pdf'}],'x');
  await api.onSubmitLecture({preventDefault(){}});
  assert.equal(node('lectureForm').resetCount,resets);
  assert.equal(node('f_text').value,'keep this draft');
  assert.ok(node('saveStatus').textContent);
  assert.equal(node('saveBtn').disabled,false);
  console.log('Authoring upload/save and failure checks passed');
}
run().catch(error=>{console.error(error);process.exitCode=1;});
