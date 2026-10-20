import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { addConfirmation, addStepFor, addStepParent, homeSectionStep, isAddForm } from "./add-flow.ts";

const config = JSON.parse(readFileSync(new URL("../design/home-templates.json", import.meta.url), "utf8"));
const sectionOf = (category: string) => config.templates[category].section as string;
const categoriesIn = (section: string) => Object.keys(config.templates).filter(key => sectionOf(key) === section);
const parent = (step: string) => addStepParent(step, sectionOf, categoriesIn);

test("destinations open their existing creation experiences", () => {
  assert.deepEqual(["work", "sidegig", "home", "social", "shopping"].map(d => addStepFor(d as never)), ["form:work", "sidegig", "home", "form:social", "list:shopping"]);
  assert.equal(isAddForm("sidegig"), false);
  assert.equal(isAddForm("gig:order"), true);
});

test("Home sections reuse category choices; single-category sections go straight to the form", () => {
  assert.equal(homeSectionStep("care", categoriesIn("care")), "home:care");
  assert.equal(homeSectionStep("bills", categoriesIn("bills")), "task:bill");
  assert.equal(homeSectionStep("study", categoriesIn("study")), "task:study");
  assert.equal(homeSectionStep("groceries", []), "list:groceries");
});

test("Back returns to the chooser each step came from", () => {
  assert.equal(parent("root"), null);
  assert.equal(parent("sidegig"), "root");
  assert.equal(parent("gig:work"), "sidegig");
  assert.equal(parent("gig:payment"), "sidegig");
  assert.equal(parent("home"), "root");
  assert.equal(parent("home:care"), "home");
  assert.equal(parent("task:car"), "home:care");
  assert.equal(parent("task:bill"), "home");
  assert.equal(parent("list:groceries"), "home");
  assert.equal(parent("list:shopping"), "root");
  assert.equal(parent("form:work"), "root");
});

test("confirmation names the destination and View opens the section and saved item", () => {
  assert.deepEqual(addConfirmation({ destination: "sidegig", kind: "work", id: "t1" }), { message: "Task added to Side Gig", href: "/side-gig?section=work&open=t1" });
  assert.deepEqual(addConfirmation({ destination: "sidegig", kind: "order", id: "o1" }), { message: "Order added to Ship Queue", href: "/side-gig?section=orders&open=o1" });
  assert.equal(addConfirmation({ destination: "sidegig", kind: "payment", id: "p1" }).href, "/side-gig?section=payments&open=p1");
  assert.deepEqual(addConfirmation({ destination: "home", category: "bill", noun: config.templates.bill.noun, id: "b1" }), { message: "Bill added to Home", href: "/home?open=b1" });
  assert.deepEqual(addConfirmation({ destination: "work", id: "w1" }), { message: "Work reminder added to Today", href: "/?open=w1" });
});

test("every Home section and category carries shared chooser copy", () => {
  for (const section of Object.values(config.sections) as { hint?: string }[]) assert.ok(section.hint);
  for (const template of Object.values(config.templates) as { noun?: string }[]) assert.ok(template.noun);
});
