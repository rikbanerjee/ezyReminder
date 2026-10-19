/* Standalone, local-only product proposal. No network calls or production writes. */
"use strict";
const $ = (s, root = document) => root.querySelector(s);
const $$ = (s, root = document) => [...root.querySelectorAll(s)];
const esc = value => String(value ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const TODAY = "2026-10-22";
const icons = {
  today:'<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
  gig:'<rect x="3" y="7" width="18" height="14" rx="3"/><path d="M8 7V5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2M3 12a22 22 0 0 0 18 0M10 13v3h4v-3"/>',
  home:'<path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1Z"/>',
  all:'<path d="M8 6h13M8 12h13M8 18h13M3 6h.1M3 12h.1M3 18h.1"/>',
  ship:'<path d="M3 5h11v12H3ZM14 9h4l3 4v4h-7"/><circle cx="6" cy="18" r="2"/><circle cx="18" cy="18" r="2"/>',
  task:'<circle cx="12" cy="12" r="9"/><path d="m8 12 3 3 5-6"/>',
  followup:'<path d="M21 11a8 8 0 0 1-8 8H7l-4 3V11a9 9 0 0 1 18 0ZM8 10h8M8 14h5"/>',
  payment:'<rect x="3" y="5" width="18" height="14" rx="3"/><path d="M3 10h18M7 15h3"/>',
  search:'<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>',
  chevron:'<path d="m9 5 7 7-7 7"/>',
  close:'<path d="m6 6 12 12M18 6 6 18"/>',
  clock:'<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  play:'<path d="m8 4 12 8-12 8Z"/>',
  plus:'<path d="M12 4v16M4 12h16"/>',
  calendar:'<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M7 3v4M17 3v4M3 11h18"/>',
};
const icon = (name, cls = "") => `<svg class="${cls}" viewBox="0 0 24 24" aria-hidden="true">${icons[name] || icons.task}</svg>`;
const action = (name, label, id = "", cls = "btn", extra = "") => `<button type="button" class="${cls}" data-action="${name}" data-id="${esc(id)}" ${extra}>${label}</button>`;
const secs = [["overview","Overview"],["work","Work"],["orders","Ship Queue"],["followups","Follow-ups"],["payments","Payments"]];
const source = {
  tasks:[
    {id:"proposal",title:"Finish Maya’s website proposal",client:"Maya · Fieldwork Studio",initiative:"Freelance design",due:"2026-10-23",next:"Compare the two pricing options, then send the proposal.",minutes:15,status:"open",planned:{date:TODAY,time:"19:00",minutes:15}},
    {id:"photos",title:"Choose photos for the autumn mugs",client:"",initiative:"Sunday Ceramics",due:"2026-10-25",next:"The photos are edited. Choose the cover image and two detail shots.",minutes:15,status:"open",planned:{date:TODAY,time:"19:00",minutes:15}},
    {id:"mockups",title:"Finalize Ben’s packaging mockups",client:"Ben · North Coffee",initiative:"Freelance design",due:"2026-10-27",next:"Apply Ben’s feedback once he confirms the direction.",minutes:25,status:"open",waiting:true},
    {id:"listing",title:"Write the holiday bundle listing",client:"",initiative:"Sunday Ceramics",due:null,next:"Start with what is included in the gift box.",minutes:25,status:"open"},
    {id:"finished",title:"Send the September project files",client:"Leo · Finch",initiative:"Freelance design",due:"2026-10-20",next:"",minutes:15,status:"done"},
  ],
  orders:[
    {id:"order1042",title:"Pack Sarah’s two ceramic mugs",ref:"Etsy #1042",client:"Sarah M.",initiative:"Sunday Ceramics",due:"2026-10-23",next:"Wrap both mugs and include the handwritten note.",minutes:15,status:"open",carrier:"USPS",tracking:"",shipped:null},
    {id:"order1048",title:"Send the Portland gift set",ref:"Shop #1048",client:"Alex R.",initiative:"Sunday Ceramics",due:"2026-10-26",next:"Check the gift message before packing.",minutes:20,status:"open",carrier:"",tracking:"",shipped:null},
    {id:"order1039",title:"Send the blue vase",ref:"Etsy #1039",client:"Jamie L.",initiative:"Sunday Ceramics",due:"2026-10-21",next:"",minutes:15,status:"done",carrier:"USPS",tracking:"DEMO-1039",shipped:"2026-10-21"},
  ],
  followups:[
    {id:"ben",title:"Check on the packaging feedback",client:"Ben · North Coffee",due:TODAY,status:"open",related:{kind:"task",id:"mockups"},note:"Mockups sent Monday. Waiting for a direction.",lastContact:"2026-10-19"},
    {id:"maya",title:"Confirm the website launch date",client:"Maya · Fieldwork Studio",due:"2026-10-23",status:"open",related:{kind:"task",id:"proposal"},note:"Needed before finalizing the proposal."},
  ],
  payments:[
    {id:"invoice17",title:"Website discovery session",client:"Maya · Fieldwork Studio",amount:"320.00",currency:"USD",due:"2026-10-21",status:"open",reference:"Invoice #017",related:{kind:"task",id:"proposal"}},
    {id:"orderbalance",title:"Sarah’s mug order balance",client:"Sarah M.",amount:"60.00",currency:"USD",due:"2026-10-24",status:"open",reference:"Etsy #1042",related:{kind:"order",id:"order1042"}},
    {id:"received1",title:"Blue vase order",client:"Jamie L.",amount:"40.00",currency:"USD",due:"2026-10-20",status:"received",received:"2026-10-20",reference:"Etsy #1039",related:{kind:"order",id:"order1039"}},
  ],
};
let data, section="overview", filters={work:"open",orders:"open",followups:"open",payments:"open"};
let session=null, lastWorked=null, modal=null, returnFocus=null, initialForm="", closeTimer, toastTimer, draggingFrom=null;
let scrollPositions={};
const content=$("#content"), sheet=$("#sheet");
const plural=(n,s)=>`${n} ${s}${n===1?"":"s"}`;
const collection=kind=>data[{task:"tasks",order:"orders",followup:"followups",payment:"payments"}[kind]];
const get=(kind,id)=>collection(kind)?.find(x=>x.id===id);
const dateObj=s=>new Date(`${s}T12:00:00Z`);
const dayDiff=s=>Math.round((dateObj(s)-dateObj(TODAY))/86400000);
const dateLabel=s=>!s?"No date":s===TODAY?"Today":dayDiff(s)===1?"Tomorrow":dateObj(s).toLocaleDateString("en-US",{timeZone:"UTC",weekday:"short",month:"short",day:"numeric"});
const datePhrase=s=>s===TODAY||dayDiff(s)===1?dateLabel(s).toLowerCase():dateLabel(s);
const dueLabel=(s,prefix="Due")=>!s?(prefix==="Ship by"?"No ship-by date":"No deadline"):`${prefix} ${datePhrase(s)}`;
const byDate=(a,b)=>(a.due||"9999").localeCompare(b.due||"9999")||a.title.localeCompare(b.title);
const isOpen=r=>r.status==="open";
const amount=r=>r.amount?new Intl.NumberFormat("en-US",{style:"currency",currency:r.currency}).format(Number(r.amount)):"Amount not set";
function moneyTotals(rows){
  const totals={};let unknown=0;
  for(const r of rows){if(!r.amount){unknown++;continue;}const [whole,fraction=""]=r.amount.split(".");const cents=BigInt(whole)*100n+BigInt((fraction+"00").slice(0,2));totals[r.currency]=(totals[r.currency]||0n)+cents;}
  return {totals:Object.entries(totals).map(([currency,cents])=>`${currency} ${(cents/100n).toLocaleString("en-US")}.${String(cents%100n).padStart(2,"0")}`),unknown};
}
function reset(){
  closeSheet(true);data=structuredClone(source);session=null;lastWorked=null;section="overview";scrollPositions={};
  const scenario=$("#scenario").value;
  if(scenario==="seller"){
    data.tasks=data.tasks.filter(t=>t.initiative==="Sunday Ceramics");data.followups=[];
    data.payments=data.payments.filter(p=>p.related?.kind==="order");
  }else if(scenario==="freelancer"){
    data.tasks=data.tasks.filter(t=>t.initiative==="Freelance design");data.orders=[];data.payments=data.payments.filter(p=>p.related?.kind==="task");
  }else if(scenario==="empty")Object.keys(data).forEach(k=>data[k]=[]);
  else if(scenario==="busy"){
    data.tasks.find(t=>t.id==="proposal").planned.minutes=25;
    data.tasks.find(t=>t.id==="photos").planned.minutes=30;
    data.tasks.find(t=>t.id==="listing").planned={date:TODAY,time:"19:00",minutes:25};
  }
  filters={work:"open",orders:"open",followups:"open",payments:"open"};render();
}
function toast(message){clearTimeout(toastTimer);$("#toast").textContent=message;$("#toast").classList.add("show");toastTimer=setTimeout(()=>$("#toast").classList.remove("show"),3800);}
function announce(message){$("#announcer").textContent=message;}
function navigate(next){scrollPositions[section]=content.scrollTop;section=next;render();content.scrollTop=scrollPositions[next]||0;const current=$(`[data-section="${section}"]`);current?.scrollIntoView({block:"nearest",inline:"nearest"});}
function render(){
  $("#sections").innerHTML=secs.map(([key,label])=>`<button class="pill" data-action="section" data-id="${key}" data-section="${key}" ${key===section?'aria-current="page"':""}>${label}</button>`).join("");
  content.innerHTML=(session&&section!=="overview"?heading("Your focus")+focusCard():"")+({overview:overview,work:workView,orders:ordersView,followups:followupsView,payments:paymentsView}[section])();
}
function heading(title,target,label="View all"){return `<div class="section-heading"><span>${title}</span>${target?action("section",`${label} ${icon("chevron")}`,target,"link"):""}</div>`;}
function listRow(kind,r,meta,extra=""){
  const label=kind==="order"?`${r.ref} · ${r.client}`:r.title;
  return `<button class="item" data-action="detail" data-id="${esc(r.id)}" data-kind="${kind}"><span class="item-icon ${kind==="order"?"amber":""}">${icon(kind==="order"?"ship":kind)}</span><span class="item-body"><span class="item-title">${esc(label)}</span><span class="item-meta">${meta}</span>${extra}</span>${icon("chevron","chevron")}</button>`;
}
function attention(){
  return [
    ...data.tasks.filter(r=>isOpen(r)&&r.due&&r.due<=TODAY&&!r.waiting).map(r=>({kind:"task",r,reason:dueLabel(r.due)})),
    ...data.orders.filter(r=>isOpen(r)&&r.due&&r.due<="2026-10-23").map(r=>({kind:"order",r,reason:dueLabel(r.due,"Ship by")})),
    ...data.followups.filter(r=>isOpen(r)&&r.due&&r.due<=TODAY).map(r=>({kind:"followup",r,reason:`Follow up ${datePhrase(r.due)}`})),
    ...data.payments.filter(r=>isOpen(r)&&r.due&&r.due<=TODAY).map(r=>({kind:"payment",r,reason:`${amount(r)} · expected ${datePhrase(r.due)}`})),
  ].sort((a,b)=>byDate(a.r,b.r));
}
const allWork=()=>[...data.tasks.map(r=>({kind:"task",r})),...data.orders.map(r=>({kind:"order",r}))];
function nextWork(){const recent=lastWorked&&get(lastWorked.kind,lastWorked.id);if(recent&&isOpen(recent)&&!recent.waiting)return {kind:lastWorked.kind,r:recent};return allWork().filter(({r})=>isOpen(r)&&!r.waiting).sort((a,b)=>Number(!a.r.planned)-Number(!b.r.planned)||byDate(a.r,b.r))[0];}
function overview(){
  if(!Object.values(data).some(a=>a.length))return `<div class="card empty-state" style="margin-top:12px">${icon("gig")}<h3>Make room for your next step.</h3><p>Add something you want to move forward.<br>Clients, orders and payments can come later.</p>${action("create","Add your first task","task","btn primary")}</div>${heading("Your side gig")}<div class="card">${sectionEntry("orders","Ship Queue","Orders, when you need them.","ship")}${sectionEntry("followups","Follow-ups","Remember who you’re waiting for.","followup")}${sectionEntry("payments","Payments","Keep track of money you expect.","payment")}</div>`;
  const needs=attention();const orders=data.orders.filter(isOpen).sort(byDate);const followups=data.followups.filter(isOpen);const payments=data.payments.filter(isOpen);
  const eligible=nextWork();
  let html=heading("Needs attention")+`<div class="card">${needs.length?needs.slice(0,3).map(({kind,r,reason})=>listRow(kind,r,`<span class="${r.due<TODAY?"danger":""}">${esc(reason)}</span>`)).join(""):'<div class="quiet-empty">Nothing needs your attention today.</div>'}</div>`;
  if(needs.length>3)html+=action("attention",`See all ${needs.length} commitments`,"","link");
  if(session)html+=heading("Your focus")+focusCard();
  else if(eligible)html+=heading("Pick up where you left off","work","Choose work")+resumeCard(eligible.kind,eligible.r);
  const planned=allWork().filter(({r})=>isOpen(r)&&r.planned).sort((a,b)=>(a.r.planned.date+a.r.planned.time).localeCompare(b.r.planned.date+b.r.planned.time));
  if(planned.length){const first=planned[0].r.planned;const group=planned.filter(({r})=>r.planned.date===first.date&&r.planned.time===first.time);const total=group.reduce((n,{r})=>n+r.planned.minutes,0);
    html+=heading("Your next focus time")+`<div class="card padded"><div class="context-line"><span><span class="dot"></span>${esc(dateLabel(first.date))} · ${timeLabel(first.time)}</span>${action("schedule","View","","link")}</div><p class="feature-title">${esc(planned[0].r.title)}</p><p class="meta">${plural(group.length,"task")} · ${total} min planned</p>${total>30?`<div class="budget">${total} minutes planned for 30 minutes available.<br>Choose what fits this time.</div>`:""}</div>`;
  }
  html+=heading("Ship Queue","orders","Open queue")+`<div class="card">${orders.length?`<div class="padded queue-heading">${icon("ship")}Ready to move<span class="count">${plural(orders.length,"open order")}</span></div>${orders.slice(0,2).map(r=>listRow("order",r,esc(dueLabel(r.due,"Ship by")))).join("")}`:sectionEntry("orders","Ship Queue","Orders, when you need them.","ship")}</div>`;
  html+=heading("Keep the loop closed")+`<div class="card">${sectionEntry("followups","Follow-ups",`${plural(followups.length,"open follow-up")}${followups.some(r=>r.due<=TODAY)?" · check in today":""}`,"followup")}${sectionEntry("payments","Payments",`${plural(payments.length,"expected payment")}${payments.some(r=>r.due<TODAY)?" · payment overdue":""}`,"payment")}</div>`;
  return html;
}
function sectionEntry(id,title,meta,symbol){return `<button class="item" data-action="section" data-id="${id}"><span class="item-icon ${id==="orders"?"amber":""}">${icon(symbol)}</span><span class="item-body"><span class="item-title">${title}</span><span class="item-meta">${esc(meta)}</span></span>${icon("chevron","chevron")}</button>`;}
function resumeCard(kind,r){return `<div class="card padded"><div class="context-line"><span><span class="dot"></span>${esc(r.initiative||"Side Gig")}</span><span>${r.minutes||15} min</span></div><p class="feature-title">${esc(r.title)}</p><p class="meta">${esc(dueLabel(r.due,kind==="order"?"Ship by":"Due"))}</p>${r.next?`<div class="inset"><small>Next step from last time</small><p>${esc(r.next)}</p></div>`:""}<div class="actions">${action("start",`${icon("play")} Start ${r.minutes||15} min`,r.id,"btn primary",`data-kind="${kind}"`)}${action("plan","Plan a time",r.id,"btn",`data-kind="${kind}"`)}</div></div>`;}
function timeLabel(time){const [h,m]=time.split(":").map(Number);return `${h%12||12}${m?":"+String(m).padStart(2,"0"):""} ${h>=12?"PM":"AM"}`;}
function filterBar(key,labels){return `<div class="filters">${labels.map(([id,label])=>`<button data-action="filter" data-id="${id}" data-key="${key}" aria-pressed="${filters[key]===id}">${label}</button>`).join("")}</div>`;}
function viewHeader(title,kind,addLabel,description){return `<div class="view-heading"><h3>${title}</h3>${action("create",`${icon("plus")} ${addLabel}`,kind,"link")}</div><p class="section-intro">${description}</p>`;}
function empty(symbol,title,description,kind,label){return `<div class="card empty-state">${icon(symbol)}<h3>${title}</h3><p>${description}</p>${kind?action("create",label,kind,"btn primary"):""}</div>`;}
function workView(){
  const rows=allWork().filter(({r})=>filters.work==="open"?isOpen(r):r.status==="done").sort((a,b)=>byDate(a.r,b.r));
  return viewHeader("Work","task","Add task","Client commitments and the small steps that move your gig forward.")+filterBar("work",[["open","Open"],["done","Completed"]])+(rows.length?`<div class="card">${rows.map(({kind,r})=>listRow(kind,r,`${esc(r.client||r.initiative||"Side Gig")} · ${esc(dueLabel(r.due,kind==="order"?"Ship by":"Due"))}${r.waiting?' · <span class="tag">Waiting</span>':""}`,r.next&&isOpen(r)?`<span class="item-next">Next: ${esc(r.next)}</span>${r.planned?`<span class="item-meta">Planned ${esc(dateLabel(r.planned.date))} · ${timeLabel(r.planned.time)}</span>`:""}`:"")).join("")}</div>`:empty("task",filters.work==="open"?"What would you like to move forward?":"Your finished work will appear here.","A client deliverable or a small improvement to your shop is enough to start.",filters.work==="open"?"task":null,"Add a task"));
}
function ordersView(){
  const rows=data.orders.filter(r=>filters.orders==="open"?!r.shipped:!!r.shipped).sort(filters.orders==="open"?byDate:(a,b)=>b.shipped.localeCompare(a.shipped));
  return viewHeader("Ship Queue","order","Add order","Every order, from a shipping promise to a recorded shipment.")+filterBar("orders",[["open","To ship"],["done","Shipped"]])+(rows.length?`<div class="card">${rows.map(r=>`<div class="order-row"><div class="order-top"><button class="order-open" data-action="detail" data-kind="order" data-id="${esc(r.id)}"><span class="item-title">${esc(r.ref||r.title)}</span><span class="item-meta">${esc(r.client||"No recipient yet")}</span></button><span class="order-by ${!r.shipped&&r.due&&r.due<TODAY?"danger":""}">${r.shipped?`Shipped<br>${esc(dateLabel(r.shipped))}`:esc(dueLabel(r.due,"Ship by"))}</span></div><p class="meta">${esc(r.title)}</p><p class="hint">${esc(r.carrier||"Carrier not set")}${r.tracking?` · ${esc(r.tracking)}`:" · No tracking added"}</p>${!r.shipped?`<div class="actions">${action("ship","Mark shipped",r.id,"btn primary small")}${action("detail","Details",r.id,"btn small",'data-kind="order"')}</div>`:""}</div>`).join("")}</div>`:empty("ship",filters.orders==="open"?"A clear place for every order.":"No shipments recorded yet.","Add a recipient and ship-by date. Track shipping here when you’re ready.",filters.orders==="open"?"order":null,"Add an order"))+`<p class="hint">Shipping records fulfillment. Payments are tracked separately.</p>`;
}
function followupsView(){
  const rows=data.followups.filter(r=>filters.followups==="open"?isOpen(r):r.status==="resolved").sort(byDate);
  return viewHeader("Follow-ups","followup","Add","Keep track of what you’re waiting for and when to check in.")+filterBar("followups",[["open","To follow up"],["done","Resolved"]])+(rows.length?`<div class="card">${rows.map(r=>listRow("followup",r,`${esc(r.client||"Follow-up")} · <span class="${isOpen(r)&&r.due<TODAY?"danger":""}">${isOpen(r)?esc(dueLabel(r.due,"Check in")):"Response recorded"}</span>`,r.note?`<span class="item-next">${esc(r.note)}</span>`:"")).join("")}</div>`:empty("followup",filters.followups==="open"?"Nothing to chase right now.":"Resolved follow-ups appear here.","A client reply, a supplier update or a buyer check-in can have its own reminder.",filters.followups==="open"?"followup":null,"Add a follow-up"))+`<p class="hint">Record contact after you reach out. This app does not send messages to your clients.</p>`;
}
function paymentsView(){
  const rows=data.payments.filter(r=>filters.payments==="open"?isOpen(r):r.status==="received").sort(byDate);const totals=moneyTotals(rows);
  return viewHeader("Payments","payment","Add","Remember money you expect and record it when it arrives.")+filterBar("payments",[["open","Expected"],["done","Received"]])+(rows.length?`<div class="card padded"><div class="context-line">${filters.payments==="open"?"Still expected":"Recorded received"}</div>${totals.totals.map(t=>`<div class="money-total">${t}</div>`).join("")}<div class="balance-caption">${plural(rows.length,"payment")}${totals.unknown?` · ${totals.unknown} without an amount`:""}</div></div><div class="card">${rows.map(r=>`<button class="item" data-action="detail" data-kind="payment" data-id="${esc(r.id)}"><span class="item-body"><span class="item-title">${esc(r.title)}</span><span class="item-meta">${esc(r.client||"Expected payment")}</span><span class="item-meta ${isOpen(r)&&r.due<TODAY?"danger":""}">${esc(isOpen(r)?dueLabel(r.due,"Expected"):`Received ${dateLabel(r.received)}`)}</span></span><span class="money-amount">${esc(amount(r))}</span>${icon("chevron","chevron")}</button>`).join("")}</div>`:empty("payment",filters.payments==="open"?"Keep expected payments in view.":"Your received payments will appear here.","Add the payment you need to remember. You can leave the amount blank.",filters.payments==="open"?"payment":null,"Add expected payment"))+`<p class="hint">Manually recorded payments. No bank connection or payment processing.</p>`;
}

// One accessible sheet; form data is retained across date-picker changes.
function openSheet(title,body,nextModal={}){
  clearTimeout(closeTimer);
  if(sheet.hidden)returnFocus=document.activeElement;
  modal=nextModal;
  sheet.innerHTML=`<div class="handle" aria-hidden="true"></div><div class="sheet-heading"><h3 id="sheet-title">${title}</h3>${action("close",icon("close"),"","close",'aria-label="Close sheet"')}</div>${body}`;
  sheet.hidden=false;sheet.inert=false;$("#scrim").hidden=false;
  $$(".app-header, #content, .dock, .review-panel").forEach(el=>el.inert=true);
  requestAnimationFrame(()=>{sheet.classList.add("open");$("#scrim").classList.add("open");});
  sheet.scrollTop=0;initialForm=formFingerprint();
  const first=$("input:not([type=hidden]),textarea,select",sheet)||$(".close",sheet);first?.focus({preventScroll:true});
}
function formFingerprint(){const form=$("form",sheet);return form?JSON.stringify([...new FormData(form)]):"";}
function closeSheet(force=false){
  if(!sheet.hidden&&!force&&initialForm!==formFingerprint()){
    if(!$("#discard",sheet)){sheet.insertAdjacentHTML("beforeend",`<div id="discard" class="warning" role="alert"><b>Discard these changes?</b><p>Your changes haven’t been saved.</p><div class="actions">${action("keep","Keep editing","","btn primary")}${action("discard","Discard","","btn")}</div></div>`);$("#discard",sheet).scrollIntoView({block:"nearest"});$('[data-action="keep"]',sheet).focus();}return;
  }
  sheet.classList.remove("open");sheet.inert=true;$("#scrim").classList.remove("open");
  $$(".app-header, #content, .dock, .review-panel").forEach(el=>el.inert=false);
  modal=null;
  closeTimer=setTimeout(()=>{sheet.hidden=true;$("#scrim").hidden=true;sheet.innerHTML="";},matchMedia("(prefers-reduced-motion: reduce)").matches?0:300);
  if(returnFocus?.isConnected)returnFocus.focus({preventScroll:true});else if(returnFocus)$("#search-button").focus({preventScroll:true});
}
function error(message){const el=$("#form-error",sheet);if(el){el.textContent=message;el.scrollIntoView({block:"nearest"});}announce(message);}
const formEnd=(label)=>`<p class="error" id="form-error" role="alert"></p><div class="stack"><button class="btn primary" type="submit">${label}</button></div>`;
const textField=(name,label,value="",placeholder="",opts="")=>`<label class="field">${label}<input name="${name}" value="${esc(value)}" placeholder="${esc(placeholder)}" ${opts}></label>`;
const textArea=(name,label,value="",placeholder="")=>`<label class="field">${label}<textarea name="${name}" placeholder="${esc(placeholder)}">${esc(value)}</textarea></label>`;
function dateField(name,label,value,optional=false){return `<div class="field">${label}<input type="hidden" name="${name}" value="${value||""}"><button type="button" class="date-trigger" data-action="date" data-id="${name}" data-optional="${optional}" aria-label="${label}: ${esc(value?dateLabel(value):"Choose date")}"><span>${value?esc(dateLabel(value)):"Choose date"}</span>${icon("calendar")}</button><div data-picker="${name}"></div></div>`;}
function addMenu(){openSheet("Add to Side Gig",[
  ["task","task","Task","A client deliverable or your next small step"],
  ["order","ship","Order","A recipient, a ship-by date and tracking"],
  ["followup","followup","Follow-up","A reply or update you need to remember"],
  ["payment","payment","Expected payment","Money to collect and when to check in"],
].map(([kind,symbol,title,desc])=>action("create",`${icon(symbol)}<span><b>${title}</b><small>${desc}</small></span>${icon("chevron","chevron")}`,kind,"choice")).join(""),{type:"add"});}
function create(kind,seed={}){
  const isOrder=kind==="order", isWork=kind==="task"||isOrder;
  const title={task:"New task",order:"New order",followup:"New follow-up",payment:"Expected payment"}[kind];
  let fields=`<span class="context-chip"><span class="dot"></span>Side Gig</span>`;
  fields+=textField("title",isOrder?"What needs to ship?":"What do you need to remember?",seed.title||"",{task:"e.g. Finish the client proposal",order:"e.g. Pack two mugs for Sarah",followup:"e.g. Check on the packaging feedback",payment:"e.g. Website project balance"}[kind],'maxlength="180"');
  if(isWork){
    fields+=dateField("due",isOrder?"Ship by":"Deadline (optional)",seed.due||null,!isOrder);
    fields+=`<label class="toggle-row"><span>This is an order</span><input type="checkbox" name="isOrder" ${isOrder?"checked":""} data-change="order"></label><div id="order-fields" class="optional-panel" ${isOrder?"":"hidden"}>${textField("ref","Order reference (optional)","","e.g. Etsy #1042")}${textField("recipient","Recipient (optional)",seed.client||"","e.g. Sarah M.")}</div>`;
    fields+=`<label class="toggle-row"><span>Add client or initiative details</span><input type="checkbox" data-change="details"></label><div id="client-fields" class="optional-panel" hidden>${textField("client","Client / buyer (optional)",seed.client||"","e.g. Maya")}${textField("initiative","Initiative (optional)","","e.g. Freelance design")}</div>`;
    fields+=textArea("next","Next small step (optional)","","Where could you start with 15 minutes?");
  }else{
    fields+=textField("client","Person or business (optional)",seed.client||"","Who is this for?");
    fields+=dateField("due",kind==="payment"?"Expected by":"Next follow-up",seed.due||TODAY);
    if(kind==="payment")fields+=`<div class="field-row">${textField("amount","Amount (optional)","","0.00",'inputmode="decimal"')}<label class="field currency">Currency<select name="currency"><option>USD</option><option>EUR</option><option>GBP</option></select></label></div>${textField("reference","Reference (optional)","","Invoice or order reference")}`;
    fields+=textArea("note","Notes (optional)",seed.note||"",kind==="followup"?"What are you waiting for?":"Anything useful to remember");
    if(seed.related){const parent=get(seed.related.kind,seed.related.id);fields+=`<div class="inset"><small>Related commitment</small><p>${esc(parent?.title||"Linked record")}</p></div>`;}
  }
  openSheet(title,`<form data-form="create" novalidate>${fields}${formEnd("Save "+(isOrder?"order":kind==="payment"?"payment":kind==="followup"?"follow-up":"task"))}</form>`,{type:"create",kind,seed});
}
function edit(kind,id){
  const r=get(kind,id);create(kind,{...r});modal.editId=id;
  $("#sheet-title").textContent="Edit details";
  const form=$("form",sheet);
  for(const [name,value] of Object.entries({...r,recipient:r.client})){
    const input=$(`[name="${name}"]`,form);
    if(input&&input.type!=="checkbox"&&typeof value!=="object")input.value=value??"";
  }
  const toggle=$('[name="isOrder"]',form);
  if(toggle){toggle.disabled=true;const details=$('[data-change="details"]',form);details.checked=!!(r.client||r.initiative);$("#client-fields",form).hidden=!details.checked;}
  $('button[type="submit"]',form).textContent="Save changes";
  initialForm=formFingerprint();
}
function detail(kind,id){
  const r=get(kind,id);if(!r)return;
  const related=r.related&&get(r.related.kind,r.related.id);
  let body=`<span class="context-chip"><span class="dot"></span>Side Gig · ${{task:"Work",order:"Order",followup:"Follow-up",payment:"Payment"}[kind]}</span><p class="detail-title">${esc(r.title)}</p><p class="meta">${esc(r.client||r.initiative||"Side Gig")}</p>`;
  const pairs=[];
  if(kind==="order")pairs.push(["Order",r.ref||"No reference"],["Ship by",dateLabel(r.due)],["Status",r.shipped?`Shipped ${dateLabel(r.shipped)}`:"To ship"],["Carrier",r.carrier||"Not set"],["Tracking",r.tracking||"Not added"]);
  if(kind==="task")pairs.push(["Deadline",r.due?dateLabel(r.due):"No deadline"],["Status",r.status==="done"?"Completed":r.waiting?"Waiting for a response":"Open"]);
  if(kind==="followup")pairs.push(["Check in",dateLabel(r.due)],["Status",isOpen(r)?"To follow up":"Resolved"],...(r.lastContact?[["Last contact",dateLabel(r.lastContact)]]:[]));
  if(kind==="payment")pairs.push(["Amount",amount(r)],["Expected by",dateLabel(r.due)],["Status",isOpen(r)?"Expected":`Received ${dateLabel(r.received)}`],["Reference",r.reference||"Not set"]);
  if(r.planned)pairs.push(["Work planned",`${dateLabel(r.planned.date)} · ${timeLabel(r.planned.time)} · ${r.planned.minutes} min`]);
  body+=`<dl class="detail-grid">${pairs.map(([k,v])=>`<dt>${k}</dt><dd>${esc(v)}</dd>`).join("")}</dl>`;
  if(r.next)body+=`<div class="inset"><small>Next step from last time</small><p>${esc(r.next)}</p></div>`;
  if(r.note)body+=`<div class="inset"><small>Notes</small><p>${esc(r.note)}</p></div>`;
  if(related)body+=action("detail",`Related: ${esc(related.title)} ${icon("chevron")}`,related.id,"link",`data-kind="${r.related.kind}"`);
  if(isOpen(r)){
    if(kind==="task"||kind==="order"){
      body+=`<div class="stack">${!r.waiting?action("start",session?"Open current session":`Start ${r.minutes||15} min`,id,"btn primary",`data-kind="${kind}"`):""}${!r.waiting?action("plan","Work on this",id,"btn",`data-kind="${kind}"`):""}${kind==="order"?action("ship","Mark shipped",id,"btn"):action("complete","Mark task done",id,"btn")}${action("related-followup",r.waiting?"View / add follow-up":"Add a follow-up",id,"btn ghost",`data-kind="${kind}"`)}</div>`;
    }else if(kind==="followup")body+=`<div class="stack">${action("contact","Record follow-up",id,"btn primary")}${action("resolve","Response received",id,"btn")}</div><p class="hint">Record contact after you reach out elsewhere. No message is sent.</p>`;
    else body+=`<div class="stack">${action("receive","Record received",id,"btn primary")}${action("related-followup","Add / view follow-up",id,"btn",'data-kind="payment"')}</div><p class="hint">Recording payment won’t complete related work or ship an order.</p>`;
  }
  if(kind==="task"&&isOpen(r)&&!r.waiting)body+=action("wait","Waiting for someone",id,"link");
  if(kind==="order"&&r.shipped)body+=`<div class="stack">${action("shipping-edit","Edit carrier / tracking",id,"btn")}${action("related-followup","Add / view buyer follow-up",id,"btn ghost",'data-kind="order"')}</div>`;
  if(isOpen(r))body+=action("edit","Edit details",id,"link",`data-kind="${kind}"`);
  openSheet({task:"Task",order:"Order details",followup:"Follow-up",payment:"Payment details"}[kind],body,{type:"detail",kind,id});
}
function shipment(id){const r=get("order",id);if(!r||r.shipped)return;openSheet("Mark shipped",`<p class="feature-title">${esc(r.ref||r.title)} · ${esc(r.client)}</p><p class="meta">Record the shipment after you hand it to the carrier.</p><form data-form="ship" novalidate>${textField("carrier","Carrier (optional)",r.carrier,"e.g. USPS")}${textField("tracking","Tracking number (optional)",r.tracking,"Paste tracking number")}<div class="inset"><p>Shipping completes this order’s reminder. Its payment stays separate.</p></div>${formEnd("Confirm shipped")}</form>`,{type:"ship",id});}
function receive(id){const r=get("payment",id);if(!r||!isOpen(r))return;const followup=data.followups.find(f=>isOpen(f)&&f.related?.kind==="payment"&&f.related.id===id);openSheet("Record payment received",`<p class="feature-title">${esc(r.title)}</p><p class="money-total">${esc(amount(r))}</p><form data-form="receive" novalidate>${dateField("received","Received on",TODAY)}${textField("note","Receipt note (optional)","","e.g. Bank transfer confirmed")}${followup?`<label class="radio-choice"><input type="checkbox" name="resolveFollowup">Also resolve this payment’s follow-up</label>`:""}<p class="hint">Record the full payment after it arrives. No money is moved by this app.</p>${formEnd("Confirm received")}</form>`,{type:"receive",id,followupId:followup?.id});}
function shippingEdit(id){const r=get("order",id);openSheet("Shipping details",`<p class="feature-title">${esc(r.ref||r.title)}</p><p class="meta">Shipped ${dateLabel(r.shipped)}</p><form data-form="shipping-edit">${textField("carrier","Carrier (optional)",r.carrier,"e.g. USPS")}${textField("tracking","Tracking number (optional)",r.tracking,"Paste tracking number")}${formEnd("Save shipping details")}</form>`,{type:"shipping-edit",id});}
function waitForSomeone(id){const r=get("task",id);const existing=data.followups.find(f=>isOpen(f)&&f.related?.kind==="task"&&f.related.id===id);if(existing){r.waiting=true;render();detail("followup",existing.id);return;}create("followup",{title:`Follow up: ${r.title}`,client:r.client,due:"2026-10-26",related:{kind:"task",id},blockWork:true});$("#sheet-title").textContent="Waiting for someone";$('button[type="submit"]',sheet).textContent="Save waiting & follow-up";}
function contact(id){const r=get("followup",id);openSheet("Record follow-up",`<p class="feature-title">${esc(r.title)}</p><p class="meta">${esc(r.client)}</p><form data-form="contact" novalidate>${textArea("note","What happened? (optional)","","e.g. Sent a check-in; expecting a reply Monday")}${dateField("due","Next check-in","2026-10-26")}<p class="hint">This records that you contacted them today. It sends no message.</p>${formEnd("Save follow-up")}</form>`,{type:"contact",id});}
function resolve(id){const r=get("followup",id);const parent=r.related&&get(r.related.kind,r.related.id);openSheet("Response received",`<p class="feature-title">${esc(r.title)}</p><form data-form="resolve"><p class="meta">Resolve this follow-up. The related commitment stays open.</p>${parent?.waiting?`<label class="radio-choice"><input type="checkbox" name="unblock" checked>Make the related work ready to start</label>`:""}${formEnd("Resolve follow-up")}</form>`,{type:"resolve",id});}
function relatedFollowup(kind,id){const existing=data.followups.find(f=>isOpen(f)&&f.related?.kind===kind&&f.related.id===id);if(existing){detail("followup",existing.id);return;}const r=get(kind,id);create("followup",{title:kind==="payment"?`Check on payment: ${r.title}`:kind==="order"?`Follow up with ${r.client||"the buyer"}`:`Follow up: ${r.title}`,client:r.client,due:"2026-10-26",related:{kind,id}});}
function complete(id){const r=get("task",id);openSheet("Complete task",`<p class="feature-title">${esc(r.title)}</p><p class="meta">Mark the whole task complete. Payments and follow-ups stay separate.</p><div class="stack">${action("confirm-complete","Mark task done",id,"btn primary")}${action("close","Keep it open","","btn ghost")}</div>`,{type:"complete",id});}

// Planning preserves actual due dates; a late plan requires a separate explicit choice.
function plan(kind,id){
  const r=get(kind,id);openSheet("Work on this",`<p class="feature-title">${esc(r.title)}</p><p class="meta">${esc(dueLabel(r.due,kind==="order"?"Ship by":"Due"))}</p><form data-form="plan" novalidate>${dateField("date","Work date",r.planned?.date||TODAY)}<div class="field-row">${textField("time","Time",r.planned?.time||"19:00","",'type="time"')}${textField("minutes","Planned minutes",r.planned?.minutes||r.minutes||15,"15",'type="number" min="1" max="180"')}</div><p class="hint">America/New_York · Planning never changes the deadline.</p><p class="hint">Your usual Thursday and Saturday focus times have a 30-minute budget.</p>${formEnd("Save plan")}</form>`,{type:"plan",kind,id});
}
function schedule(){const planned=allWork().filter(({r})=>isOpen(r)&&r.planned).sort((a,b)=>(a.r.planned.date+a.r.planned.time).localeCompare(b.r.planned.date+b.r.planned.time));openSheet("Planned work",`<p class="meta">Keep only what fits. Move a task to another time or leave it unscheduled.</p>${planned.length?planned.map(({kind,r})=>`<div class="card padded" style="margin-top:12px"><p class="feature-title">${esc(r.title)}</p><p class="meta">${dateLabel(r.planned.date)} · ${timeLabel(r.planned.time)} · ${r.planned.minutes} min</p><div class="actions">${action("plan","Move",r.id,"btn",`data-kind="${kind}"`)}${action("unschedule","Leave unscheduled",r.id,"btn ghost",`data-kind="${kind}"`)}</div></div>`).join(""):'<p class="hint">Nothing planned yet. Open a task and choose Work on this.</p>'}`,{type:"schedule"});}

// Local demonstration of the existing Focus semantics, not a production timer engine.
function remaining(){return session?Math.max(0,session.seconds-(session.running?Math.floor((Date.now()-session.since)/1000):0)):0;}
const countdown=()=>`${String(Math.floor(remaining()/60)).padStart(2,"0")}:${String(remaining()%60).padStart(2,"0")}`;
function focusCard(){const r=get(session.kind,session.id);return `<div class="card padded"><div class="context-line"><span><span class="dot"></span>${remaining()===0?"Time is up":session.running?"In focus":"Paused"}</span><span data-countdown role="timer" aria-label="Focus time remaining">${countdown()}</span></div><p class="feature-title">${esc(r.title)}</p><div class="actions">${action("session",remaining()===0?"Review session":"Open session","","btn primary")}</div></div>`;}
function start(kind,id){if(session){sessionSheet();return;}const r=get(kind,id);if(!r||!isOpen(r)||r.waiting)return;session={kind,id,seconds:(r.minutes||15)*60,total:(r.minutes||15)*60,since:Date.now(),running:true};render();announce("Focus session started");sessionSheet();}
function sessionSheet(){if(!session)return;const r=get(session.kind,session.id);if(remaining()===0){reviewSession();return;}openSheet(session.running?"In focus":"Paused",`<span class="context-chip"><span class="dot"></span>Side Gig</span><p class="detail-title">${esc(r.title)}</p>${r.next?`<div class="inset"><small>Your next step</small><p>${esc(r.next)}</p></div>`:""}<div class="time-value" data-countdown role="timer" aria-label="Focus time remaining">${countdown()}</div><p class="session-status">${session.running?"One thing at a time.":"Take the time you need."}</p><div class="actions">${action("pause",session.running?"Pause":"Resume","","btn primary")}${action("review","End session","","btn")}</div><p class="hint">You can close this sheet and come back to the same session.</p>`,{type:"session"});}
function reviewSession(){if(!session)return;session.seconds=remaining();session.running=false;const r=get(session.kind,session.id);render();openSheet("How did it go?",`<p class="feature-title">${esc(r.title)}</p><form data-form="review"><div class="radio-choices">${[["finished","Finished what I planned"],["progress","Made progress"],["interrupted","Got interrupted"]].map(([v,t])=>`<label class="radio-choice"><input type="radio" name="outcome" value="${v}">${t}</label>`).join("")}</div>${textArea("next","Where will you start next time?","","Leave yourself a small next step.")}<p class="hint">Optional. Your latest note appears when you return. Saving this session leaves the reminder open.</p>${formEnd("Save session")}</form>`,{type:"review"});}

// Compact date picker: explicit day selection + OK; hidden value changes only on OK.
let picker=null;
function openDate(name,optional){if(picker&&picker.name!==name){const old=$(`[data-picker="${picker.name}"]`,sheet);if(old)old.innerHTML="";}const value=$(`[name="${name}"]`,sheet).value||TODAY;picker={name,optional,selected:value,month:value.slice(0,7)};renderDate();}
function renderDate(){
  const [y,m]=picker.month.split("-").map(Number);const offset=new Date(Date.UTC(y,m-1,1)).getUTCDay();const length=new Date(Date.UTC(y,m,0)).getUTCDate();
  const month=new Date(Date.UTC(y,m-1,1)).toLocaleDateString("en-US",{timeZone:"UTC",month:"long",year:"numeric"});
  $(`[data-picker="${picker.name}"]`,sheet).innerHTML=`<div class="date-picker"><div class="cal-head">${action("month","‹","-1","",'aria-label="Previous month"')}<b>${month}</b>${action("month","›","1","",'aria-label="Next month"')}</div><div class="calendar">${["S","M","T","W","T","F","S"].map(d=>`<small>${d}</small>`).join("")}${"<span></span>".repeat(offset)}${Array.from({length},(_,i)=>{const d=`${picker.month}-${String(i+1).padStart(2,"0")}`;return action("day",String(i+1),d,`day ${d===picker.selected?"selected":""}`,`aria-label="${dateLabel(d)}" aria-pressed="${d===picker.selected}"`);}).join("")}</div><div class="cal-foot">${picker.optional?action("date-none","No date","","btn ghost"):action("date-cancel","Cancel","","btn ghost")}${action("date-ok","OK","","btn primary")}</div></div>`;
}
function saveDate(value){const {name}=picker;$(`[name="${name}"]`,sheet).value=value;const trigger=$(`[data-action="date"][data-id="${name}"]`,sheet);$("span",trigger).textContent=value?dateLabel(value):"Choose date";trigger.setAttribute("aria-label",value?`Selected date: ${dateLabel(value)}`:"Choose date");$(`[data-picker="${name}"]`,sheet).innerHTML="";picker=null;trigger.focus();}
function search(){openSheet("Search Side Gig",'<label class="field">Find a commitment<input class="search-input" id="query" placeholder="Title, client, order reference…" autocomplete="off"></label><div id="search-results" style="margin-top:14px"></div>',{type:"search"});searchResults("");}
function searchResults(q){const rows=[...allWork(),...data.followups.map(r=>({kind:"followup",r})),...data.payments.map(r=>({kind:"payment",r}))].filter(({r})=>`${r.title} ${r.client} ${r.ref||""} ${r.reference||""}`.toLowerCase().includes(q.toLowerCase()));$("#search-results").innerHTML=rows.length?`<div class="card">${rows.map(({kind,r})=>listRow(kind,r,esc(`${r.client||"Side Gig"} · ${kind}`))).join("")}</div>`:'<p class="hint">No matching commitments.</p>';}

document.addEventListener("click",e=>{
  const b=e.target.closest("[data-action]");if(!b)return;const {action:a,id,kind,key}=b.dataset;
  if(a==="section")navigate(id);
  else if(a==="filter"){filters[key]=id;render();}
  else if(a==="add")addMenu();
  else if(a==="create")create(id);
  else if(a==="detail")detail(kind,id);
  else if(a==="edit")edit(kind,id);
  else if(a==="close")closeSheet();
  else if(a==="discard")closeSheet(true);
  else if(a==="keep"){$("#discard",sheet)?.remove();$("input,textarea,.close",sheet)?.focus();}
  else if(a==="ship")shipment(id);
  else if(a==="shipping-edit")shippingEdit(id);
  else if(a==="wait")waitForSomeone(id);
  else if(a==="receive")receive(id);
  else if(a==="contact")contact(id);
  else if(a==="resolve")resolve(id);
  else if(a==="related-followup")relatedFollowup(kind,id);
  else if(a==="complete")complete(id);
  else if(a==="confirm-complete"){get("task",id).status="done";delete get("task",id).planned;render();closeSheet(true);toast("Task completed. Other commitments stay open.");}
  else if(a==="plan")plan(kind,id);
  else if(a==="schedule")schedule();
  else if(a==="unschedule"){delete get(kind,id).planned;render();schedule();toast("Work left unscheduled. Deadline unchanged.");}
  else if(a==="start")start(kind,id);
  else if(a==="session")sessionSheet();
  else if(a==="pause"){session.seconds=remaining();session.running=!session.running;session.since=Date.now();render();sessionSheet();announce(session.running?"Focus resumed":"Focus paused");}
  else if(a==="review")reviewSession();
  else if(a==="search")search();
  else if(a==="attention")openSheet("Needs attention",`<div class="card">${attention().map(({kind,r,reason})=>listRow(kind,r,esc(reason))).join("")}</div>`,{type:"attention"});
  else if(a==="date")openDate(id,b.dataset.optional==="true");
  else if(a==="day"){picker.selected=id;renderDate();}
  else if(a==="month"){const [y,m]=picker.month.split("-").map(Number);picker.month=new Date(Date.UTC(y,m-1+Number(id),1)).toISOString().slice(0,7);renderDate();}
  else if(a==="date-ok")saveDate(picker.selected);
  else if(a==="date-none")saveDate("");
  else if(a==="date-cancel"){$(`[data-picker="${picker.name}"]`,sheet).innerHTML="";picker=null;}
  else if(a==="late-plan")savePlan(true);
  else if(a==="earlier"){ $("#late-warning",sheet)?.remove();openDate("date",false);}
});
document.addEventListener("input",e=>{if(e.target.id==="query")searchResults(e.target.value);});
document.addEventListener("change",e=>{
  if(e.target.dataset.change==="details")$("#client-fields",sheet).hidden=!e.target.checked;
  if(e.target.dataset.change==="order"){
    $("#order-fields",sheet).hidden=!e.target.checked;
    const due=$('[name="due"]',sheet).parentElement;
    due.firstChild.textContent=e.target.checked?"Ship by":"Deadline (optional)";
    const trigger=$('[data-action="date"]',due);trigger.dataset.optional=String(!e.target.checked);
    $("#sheet-title").textContent=e.target.checked?"New order":"New task";
    $('button[type="submit"]',sheet).textContent=e.target.checked?"Save order":"Save task";
  }
  if(modal?.type==="plan")$("#late-warning",sheet)?.remove();
});
function formValues(form){return Object.fromEntries([...new FormData(form)].map(([k,v])=>[k,typeof v==="string"?v.trim():v]));}
function savePlan(allowLate=false){
  const v=formValues($("form",sheet)),r=get(modal.kind,modal.id);const min=Number(v.minutes);
  if(!v.date||!v.time||!Number.isInteger(min)||min<1||min>180){error("Choose a date, time and a whole number of minutes from 1 to 180.");return;}
  if(v.date<TODAY||(v.date===TODAY&&v.time<"18:30")){error("Choose a work time after 6:30 PM today, or a future day.");return;}
  if(r.due&&v.date>r.due&&!allowLate){
    if(!$("#late-warning",sheet))$("form",sheet).insertAdjacentHTML("beforeend",`<div class="warning" id="late-warning" role="alert"><b>This is after the ${modal.kind==="order"?"ship-by date":"deadline"}.</b><p>${esc(dueLabel(r.due))}. Your deadline stays the same.</p><div class="stack">${action("earlier","Choose an earlier time","","btn primary")}${action("late-plan","Plan it anyway","","btn")}</div></div>`);
    $("#late-warning",sheet).scrollIntoView({block:"nearest"});return;
  }
  r.planned={date:v.date,time:v.time,minutes:min};render();closeSheet(true);toast("Work planned. Your deadline is unchanged.");
}
document.addEventListener("submit",e=>{
  const form=e.target;if(!form.dataset.form)return;e.preventDefault();const v=formValues(form),type=form.dataset.form;
  if(type==="create"){
    if(!v.title){error("Add a title so you know what to come back to.");$('[name="title"]',form).focus();return;}
    let kind=modal.kind;if(!modal.editId&&(kind==="task"||kind==="order"))kind=v.isOrder?"order":"task";
    if(kind!=="task"&&!v.due){error("Choose a date, then tap OK.");return;}
    if(kind==="payment"&&v.amount&&!/^\d{1,9}(\.\d{1,2})?$/.test(v.amount)){error("Enter a positive amount with up to two decimal places.");return;}
    if(kind==="payment"&&v.amount&&Number(v.amount)<=0){error("Enter an amount greater than zero, or leave it blank.");return;}
    const existing=modal.editId?get(kind,modal.editId):null;
    const r={...existing,id:existing?.id||crypto.randomUUID(),title:v.title,client:kind==="order"?v.recipient:v.client||"",initiative:v.initiative||"",due:v.due||null,status:"open",next:v.next||"",note:v.note||"",minutes:existing?.minutes||15,related:modal.seed.related};
    if(kind==="order")Object.assign(r,{ref:v.ref||"",carrier:existing?.carrier||"",tracking:existing?.tracking||"",shipped:null});
    if(kind==="payment")Object.assign(r,{amount:v.amount||null,currency:v.currency,reference:v.reference||""});
    if(existing)Object.assign(existing,r);else collection(kind).push(r);
    if(modal.seed.blockWork&&modal.seed.related){const parent=get(modal.seed.related.kind,modal.seed.related.id);if(parent)parent.waiting=true;}
    navigate({task:"work",order:"orders",followup:"followups",payment:"payments"}[kind]);filters[section]="open";render();closeSheet(true);toast(`${{task:"Task",order:"Order",followup:"Follow-up",payment:"Payment"}[kind]} saved to Side Gig.`);
  }else if(type==="ship"){
    const r=get("order",modal.id);if(r.shipped)return;r.carrier=v.carrier;r.tracking=v.tracking;r.shipped=TODAY;r.status="done";delete r.planned;render();
    openSheet("Shipment recorded",`${icon("task")}<p class="detail-title">${esc(r.ref||r.title)} is shipped.</p><p class="meta">Its payment remains separate.</p><div class="stack">${action("related-followup","Add buyer follow-up",r.id,"btn primary",'data-kind="order"')}${action("close","Done","","btn")}</div>`,{type:"saved"});announce("Shipment recorded");
  }else if(type==="shipping-edit"){
    const r=get("order",modal.id);r.carrier=v.carrier;r.tracking=v.tracking;render();closeSheet(true);toast("Shipping details updated. Shipment date unchanged.");
  }else if(type==="receive"){
    if(!v.received||v.received>TODAY){error("Choose today or an earlier received date.");return;}const r=get("payment",modal.id);r.status="received";r.received=v.received;r.note=v.note;if(v.resolveFollowup&&modal.followupId)get("followup",modal.followupId).status="resolved";render();closeSheet(true);toast("Payment recorded. Work and shipping are unchanged.");
  }else if(type==="contact"){
    if(!v.due||v.due<TODAY){error("Choose today or a future check-in date.");return;}const r=get("followup",modal.id);r.lastContact=TODAY;r.due=v.due;r.note=v.note||r.note;render();closeSheet(true);toast("Follow-up recorded. No message was sent.");
  }else if(type==="resolve"){
    const r=get("followup",modal.id);r.status="resolved";const parent=r.related&&get(r.related.kind,r.related.id);if(v.unblock&&parent)parent.waiting=false;render();closeSheet(true);toast("Follow-up resolved. Related work stays open.");
  }else if(type==="plan")savePlan();
  else if(type==="review"){
    if(!v.outcome){error("Choose how the session went.");return;}const {kind,id}=session;const r=get(kind,id);r.next=v.next||"";delete r.planned;lastWorked={kind,id};session=null;render();
    openSheet("Session saved",`<p class="detail-title">${esc(r.title)}</p><p class="meta">${{finished:"Finished what I planned",progress:"Made progress",interrupted:"Got interrupted"}[v.outcome]}</p>${r.next?`<div class="inset"><small>Next time</small><p>${esc(r.next)}</p></div>`:""}<p class="hint">Your reminder is still open.</p><div class="stack">${action("plan","Choose another focus time",id,"btn primary",`data-kind="${kind}"`)}${action("close","I’m done for now","","btn")}${v.outcome==="finished"?(kind==="order"?action("ship","Mark shipped",id,"btn ghost"):action("complete","Mark task done",id,"btn ghost")):""}</div>`,{type:"saved"});announce("Session saved. Reminder remains open.");
  }
});
$("#scrim").addEventListener("click",()=>closeSheet());
sheet.addEventListener("pointerdown",e=>{if(e.target.closest(".handle"))draggingFrom=e.clientY;});
sheet.addEventListener("pointerup",e=>{if(draggingFrom!==null&&e.clientY-draggingFrom>55)closeSheet();draggingFrom=null;});
document.addEventListener("keydown",e=>{
  if(sheet.hidden)return;
  if(e.key==="Escape"){e.preventDefault();closeSheet();}
  if(e.key==="Tab"){
    const candidates=$$('button:not(:disabled),a[href],input:not([type=hidden]),select,textarea,[tabindex="0"]',sheet).filter(el=>el.getClientRects().length&&!el.closest("[hidden]"));
    const first=candidates[0],last=candidates.at(-1);if(e.shiftKey&&document.activeElement===first){e.preventDefault();last?.focus();}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first?.focus();}
  }
});
$("#scenario").addEventListener("change",reset);$("#reset").addEventListener("click",()=>{reset();toast("Sample data restored.");});
function setTheme(dark){document.documentElement.classList.toggle("dark",dark);$("#theme").textContent=dark?"Light appearance":"Dark appearance";}
$("#theme").addEventListener("click",()=>setTheme(!document.documentElement.classList.contains("dark")));
$("#controls-toggle").addEventListener("click",()=>{const expanded=$(".review-panel").classList.toggle("expanded");$("#controls-toggle").setAttribute("aria-expanded",String(expanded));});
setTheme(matchMedia("(prefers-color-scheme: dark)").matches);
new ResizeObserver(([entry])=>document.documentElement.style.setProperty("--review-height",`${entry.target.getBoundingClientRect().height}px`)).observe($(".review-panel"));
$("#search-button").innerHTML=icon("search");$$('[data-icon]').forEach(el=>el.insertAdjacentHTML("afterbegin",icon(el.dataset.icon)));
reset();
setInterval(()=>{if(!session)return;$$('[data-countdown]').forEach(el=>el.textContent=countdown());if(session.running&&remaining()===0){session.seconds=0;session.running=false;render();announce("Time is up. Review your session when you’re ready.");if(modal?.type==="session")reviewSession();}},1000);
