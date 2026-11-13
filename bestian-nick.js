/* 베스티안 닉네임 공통 모듈 — 학생 센터 · 실시간 순위 · 순공 리그가 같이 씀
   저장 위치: 데스크 전용 Supabase 의 bestian_league_profiles (bestian_league_setup.sql)
   사용: <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/dist/umd/supabase.min.js"></script>
         <script src="bestian-nick.js"></script>   */
(function(){
"use strict";
var DESK_URL='https://eftroiiexkpnladkiypu.supabase.co';
var DESK_KEY='sb_publishable_XEif-nOPOZRLjPK8KQRLJg_p-KJN9n8';   // bestian-student.html 데스크 서버 값과 동일
var MOCK=/[?&]mock=1/.test(location.search);
var client=null;
try{if(!MOCK&&window.supabase&&DESK_URL&&DESK_KEY)client=window.supabase.createClient(DESK_URL,DESK_KEY,{auth:{persistSession:false,storageKey:'bnick'}})}catch(e){client=null}

var MAP={},loaded=false,loading=null;
var BAD=['씨발','시발','ㅅㅂ','ㅆㅂ','병신','ㅂㅅ','좆','지랄','fuck','shit','새끼','니미','섹스','개새','존나','느금'];
var ADJ=['용감한','조용한','빠른','성실한','단단한','반짝이는','끈질긴','침착한','똑똑한','부지런한','든든한','날렵한','뜨거운','차분한','씩씩한','묵묵한'];
var ANI=['수달','고래','부엉이','여우','펭귄','호랑이','판다','다람쥐','독수리','거북이','늑대','사슴','곰','치타','두더지','고슴도치','해달','올빼미','표범','코알라'];
function hash(s){var h=2166136261;s=String(s);for(var i=0;i<s.length;i++){h^=s.charCodeAt(i);h=Math.imul(h,16777619)}return h>>>0}
function auto(id){var h=hash(id);return ADJ[h%ADJ.length]+' '+ANI[(h>>>8)%ANI.length]}
function mockLoad(){try{MAP=JSON.parse(localStorage.getItem('bnick_mock')||'{}')}catch(e){MAP={}}}
function mockSave(){try{localStorage.setItem('bnick_mock',JSON.stringify(MAP))}catch(e){}}

async function load(force){
  if(loaded&&!force)return MAP;
  if(loading&&!force)return loading;
  loading=(async function(){
    if(MOCK){mockLoad();loaded=true;return MAP}
    if(!client)return MAP;
    var r=await client.from('bestian_league_profiles').select('student_id,nickname');
    if(!r.error){var m={};(r.data||[]).forEach(function(x){m[String(x.student_id)]=x.nickname});MAP=m;loaded=true}
    return MAP})();
  try{return await loading}finally{loading=null}}
function get(id){return MAP[String(id)]||''}
function name(id){return get(id)||auto(id)}

// 닉네임 규칙 검사 — 문제가 있으면 안내 문장, 괜찮으면 ''
function check(v,realName,id){
  v=String(v||'').trim();
  if(v.length<2||v.length>10)return '2~10자로 정해 주세요.';
  if(!/^[가-힣a-zA-Z0-9_ ]+$/.test(v))return '한글·영어·숫자만 쓸 수 있어요.';
  var low=v.toLowerCase().replace(/\s/g,'');
  if(BAD.some(function(w){return low.indexOf(w)>-1}))return '쓸 수 없는 말이 들어 있어요.';
  var nm=String(realName||'').replace(/\s/g,'');
  if(nm&&(low.indexOf(nm)>-1||(nm.length>=2&&low.indexOf(nm.slice(1))>-1)))return '실명은 닉네임으로 쓸 수 없어요.';
  var dup=Object.keys(MAP).some(function(k){return k!==String(id)&&String(MAP[k]).toLowerCase()===v.toLowerCase()});
  if(dup)return '이미 누가 쓰고 있는 닉네임이에요.';
  return ''}

async function save(id,v,by){
  v=String(v||'').trim();id=String(id);
  if(MOCK){MAP[id]=v;mockSave();return {ok:true}}
  if(!client)return {ok:false,msg:'인터넷 연결을 확인해 주세요.'};
  var r=await client.from('bestian_league_profiles').upsert({student_id:id,nickname:v,updated_at:new Date().toISOString(),updated_by:by||'student'});
  if(r.error)return {ok:false,msg:/duplicate|unique/i.test(r.error.message||'')?'이미 누가 쓰고 있는 닉네임이에요.':'저장 오류. 다시 시도해 주세요.'};
  MAP[id]=v;return {ok:true}}
async function remove(id){id=String(id);if(MOCK){delete MAP[id];mockSave();return {ok:true}}
  if(!client)return {ok:false};var r=await client.from('bestian_league_profiles').delete().eq('student_id',id);if(!r.error)delete MAP[id];return {ok:!r.error}}

window.BestianNick={url:DESK_URL,key:DESK_KEY,client:client,load:load,get:get,name:name,auto:auto,check:check,save:save,remove:remove,map:function(){return MAP},ok:function(){return loaded}};
})();
