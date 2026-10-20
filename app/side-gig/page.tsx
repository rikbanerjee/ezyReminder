import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { SideGigView } from "@/components/sidegig/sidegig-view";

export default async function SideGigPage({searchParams}:{searchParams:Promise<{section?:string;open?:string}>}) {
  const params=await searchParams;
  const supabase=await createClient();
  const {data:{user}}=await supabase.auth.getUser();
  if(!user)redirect(`/login?next=${encodeURIComponent("/side-gig")}`);
  const [{data,error},{data:contexts}]=await Promise.all([supabase.rpc("get_sidegig_dashboard"),supabase.from("contexts").select("id,slug,name,color,default_channel").order("name")]);
  return <SideGigView contexts={contexts??[]} initial={data} initialError={error?"Could not load Side Gig. Please try again.":null} initialSection={params.section} openId={params.open}/>;
}
