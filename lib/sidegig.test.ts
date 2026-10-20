import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { gigAttention,gigMoney,gigResume,type GigDashboard,type GigItem } from "./sidegig.ts";
const fixture=JSON.parse(readFileSync(new URL("../design/sidegig-fixtures.json",import.meta.url),"utf8"));
const data={...fixture,api:18} as GigDashboard;
test("shared attention fixtures: waiting, collection dedup, account dates and ship-by",()=>assert.deepEqual(gigAttention(data).map(r=>r.id),fixture.attention_ids));
test("exact money totals keep currencies separate",()=>assert.deepEqual(gigMoney(data.items.filter(r=>r.kind==="payment")).totals,fixture.money_totals));
test("unknown amounts stay explicit",()=>assert.deepEqual(gigMoney([{kind:"payment",amount:null} as GigItem]),{totals:[],unknown:1}));
test("resume selects recently worked actionable Side Gig work, never waiting or payment",()=>{
  const rows=[...data.items,{id:"restart",kind:"work",status:"open",context_slug:"sidegig",last_worked_at:"2026-10-22T15:00:00Z",next_step:""} as GigItem];
  assert.equal(gigResume({...data,items:rows},[])?.id,"restart");
  assert.equal(gigResume({...data,items:rows},[])?.next_step,"");
});
