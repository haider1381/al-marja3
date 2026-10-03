const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const html=fs.readFileSync(process.argv[2]||'index.html','utf8'),code=html.split('// STUDY_ENGINE_START')[1].split('// STUDY_ENGINE_END')[0],ctx=vm.createContext({});vm.runInContext(code,ctx);
const base={targetMinutes:120,workMinutes:30,restMinutes:5,dailyMinutes:180,horizonDays:1,mode:'focus',weekdays:[0,1,2,3,4,5,6],startDate:'2026-10-03',startTime:'09:00'};
function run(over={}){return ctx.generateStudySessions({...base,...over});}
let r=run();assert.equal(r.focusMinutes,120);assert.equal(r.restMinutes,15);assert.equal(r.sessions.length,7);assert.equal(r.totalMinutes,135);assert.equal(r.sessions.at(-1).start_time,'10:45');
r=run({mode:'elapsed'});assert.equal(r.focusMinutes,105);assert.equal(r.totalMinutes,120);assert.equal(r.sessions.at(-1).duration_minutes,15);
r=run({workMinutes:15});assert.equal(r.focusMinutes,120);assert.equal(r.restMinutes,35);assert.equal(r.sessions.length,15);
r=run({restMinutes:0,targetMinutes:65});assert.equal(r.sessions.length,3);assert.equal(r.sessions.at(-1).duration_minutes,5);
r=run({dailyMinutes:65,horizonDays:7,weekdays:[1,3]});assert.equal(r.studyDays,2);assert.equal(r.focusMinutes,120);assert.equal(r.restMinutes,10);assert(r.sessions.every(s=>[1,3].includes(s.day_of_week)));assert.equal(r.sessions[0].scheduled_date,'2026-10-05');
r=run({mode:'elapsed',targetMinutes:32});assert.equal(r.focusMinutes,30);assert.equal(r.unusedMinutes,2);assert.equal(r.sessions.at(-1).kind,'study');
for(const over of [{weekdays:[]},{startDate:'2026-02-30'},{startTime:'25:00'},{startTime:'23:00'},{dailyMinutes:20},{horizonDays:0},{mode:'bad'},{targetMinutes:120,dailyMinutes:65,horizonDays:1},{targetMinutes:43200,workMinutes:1,restMinutes:0,horizonDays:365,dailyMinutes:600}])assert.throws(()=>run(over));
for(let target=1;target<=180;target+=7)for(const work of [15,30,45])for(const rest of [0,1,5,10])for(const mode of ['focus','elapsed']){
 const x=run({targetMinutes:target,workMinutes:work,restMinutes:rest,mode,dailyMinutes:600});assert.equal(x.sessions[0].kind,'study');assert.equal(x.sessions.at(-1).kind,'study');assert.equal(x.focusMinutes+x.restMinutes,x.totalMinutes);if(mode==='focus')assert.equal(x.focusMinutes,target);else assert.equal(x.totalMinutes+x.unusedMinutes,target);
 x.sessions.forEach((s,i)=>{assert.equal(s.session_order,i);assert(s.duration_minutes>0);if(s.kind==='break'){assert.equal(x.sessions[i-1].kind,'study');assert.equal(x.sessions[i+1].kind,'study');assert.equal(s.scheduled_date,x.sessions[i+1].scheduled_date);}});
}
console.log('PASS: focus/elapsed totals, breaks, minutes, multi-day weekdays, final fragments, validation and 624 invariant cases');
