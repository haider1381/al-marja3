// Run from repository root: node tests/library.test.cjs
// Uses only Node built-ins; no Supabase connection or mutations.
const fs = require('node:fs');
const assert = require('node:assert/strict');
const html = fs.readFileSync('index.html','utf8');
const match = html.match(/<script>([\s\S]*?)<\/script>/);
assert.ok(match, 'application script exists');
const source = match[1].replace(/\ninit\(\);\s*$/, '');
const api = new Function('document', source + '\n' + "return {materialGroup,filterMaterials,emptyQuestion,validateQuestions,quizScore,validatePdf,rowToLecture,lectureToRow,renderLectureText,questionEditorHtml};")({});
let count = 0;
function check(ok, name) { assert.ok(ok, name); count++; }
function throws(fn, name) { assert.throws(fn, undefined, name); count++; }

  check(api.materialGroup('محاضرة') === 'lectures', 'lecture group');
  check(api.materialGroup('ملخص') === 'lectures', 'summary group');
  check(api.materialGroup('ملف PDF') === 'lectures', 'PDF group');
  check(api.materialGroup('فيديو') === 'videos', 'video group');
  check(api.materialGroup('أسئلة') === 'questions', 'question group');
  check(api.materialGroup('نوع قديم') === 'other', 'legacy group');
  const sample = [
    {id:'1',title:'Heart Failure',source:'د. أحمد',topic:'Cardiology',type:'محاضرة'},
    {id:'2',title:'Heart MCQ',source:'د. أحمد',topic:'Cardiology',type:'أسئلة'},
    {id:'3',title:'Heart Video',source:'د. علي',topic:'Cardiology',type:'فيديو'},
    {id:'4',title:'Renal',source:'د. أحمد',topic:'Renal',type:'ملف PDF'}
  ];
  check(api.filterMaterials(sample,{search:' HEART ',filterSource:'د. أحمد',filterKind:'questions'}).map(x=>x.id).join() === '2','combined filters');
  check(api.filterMaterials(sample,{search:'فيديو'}).length === 1,'search type');
  check(api.filterMaterials(sample,{filterTopic:'Renal',filterKind:'lectures'}).length === 1,'topic + group');
  check(api.filterMaterials(sample,{filterSource:'غير موجود'}).length === 0,'no matches');
  const question = api.emptyQuestion();
  question.prompt = 'Which option?';
  question.options.forEach((o,i)=>{o.text='Option '+i;o.explanation='Reason '+i;});
  question.correctIndex = 2;
  check(api.validateQuestions([question]).length === 1,'valid MCQ');
  throws(()=>api.validateQuestions([]),'empty quiz');
  throws(()=>api.validateQuestions([{...question,correctIndex:4}]),'invalid answer');
  throws(()=>api.validateQuestions([{...question,options:question.options.slice(0,3)}]),'missing option');
  throws(()=>api.validateQuestions([{...question,options:[{text:'A',explanation:''},...question.options.slice(1)]}]),'missing explanation');
  check(api.quizScore([question,question],[2,0])===1,'quiz scoring');
  check(api.quizScore([question],[])===0,'unanswered quiz');
  api.validatePdf({name:'lecture.pdf',type:'application/pdf',size:1024});
  throws(()=>api.validatePdf({name:'file.exe',type:'application/pdf',size:1}),'PDF extension');
  throws(()=>api.validatePdf({name:'file.pdf',type:'application/pdf',size:0}),'empty PDF');
  throws(()=>api.validatePdf({name:'file.pdf',type:'application/pdf',size:26214401}),'oversize PDF');
  check(api.rowToLecture({id:1,questions:[question],file_path:'pdf/x.pdf'}).filePath==='pdf/x.pdf','file mapping');
  check(api.rowToLecture({id:1}).questions.length===0,'legacy questions');
  check(api.lectureToRow({questions:[question],filePath:'pdf/x.pdf'}).questions[0].correctIndex===2,'MCQ persistence');
  check(!api.renderLectureText('<script>alert(1)</script>').includes('<script>'),'reader escaping');
  check(!api.questionEditorHtml({...question,prompt:'<img onerror=alert(1)>'},0).includes('<img'),'editor escaping');

console.log(count + ' library checks passed');
