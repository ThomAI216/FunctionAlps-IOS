do $$
declare
  eng uuid := 'd1e37372-dd99-40ca-a285-92c3f7ba62d1';
  sta uuid := 'c4f299a9-0c53-4dfd-abed-e90620fa4821';
  mus uuid := '8ed4a32f-d9ee-4777-af2c-661086a59e11';
  fue uuid := '1c737de6-e953-41f0-8647-96dc7c9e2980';
  st uuid; sl uuid; ca uuid;
  spec jsonb; t jsonb; r jsonb; i int; nid uuid; cnt int; got int;
begin
  -- new tracks
  insert into library_tracks(slug,title,description,pillar,cover_style,position,is_active)
   values ('functional-health-from-the-ground-up','Functional health, from the ground up','What functional health is, and the ideas everything else builds on.','foundations','compass',1,true) returning id into st;
  insert into library_tracks(slug,title,description,pillar,cover_style,position,is_active)
   values ('sleep-deeper','Sleep deeper','Light, caffeine, evenings and recovery: the habits that shape your night.','sommeil','moon',5,true) returning id into sl;
  insert into library_tracks(slug,title,description,pillar,cover_style,position,is_active)
   values ('calm-and-recover','Calm and recover','Breath, gratitude, connection and writing: small ways to calm down and recover.','stress','book',6,true) returning id into ca;
  -- renames of the existing tracks
  update library_tracks set title='Fuel your body', description='Food first: protein, the right carbs, nutrient-dense foods and the micronutrients behind them.', pillar='nutrition', position=2, updated_at=now() where id=fue;
  update library_tracks set title='Build your engine', description='Build the base, raise the ceiling, then add intervals.', pillar='mouvement', position=3, updated_at=now() where id=eng;
  update library_tracks set title='Build a stronger body', description='Become stronger and more capable, not simply more tired.', pillar='mouvement', position=4, updated_at=now() where id=mus;
  update library_tracks set is_active=false, updated_at=now() where id=sta;
  -- Signals leaves the Engine track for Start here
  update library_track_lessons set track_id=st, position=1005 where id='92cc8ac4-cc1a-43ef-8309-0a4857467fc3';
  -- park existing rows of reworked tracks
  update library_track_lessons set position=position+1000 where track_id in (eng,mus,fue) and position<1000;

  spec := jsonb_build_array(
   jsonb_build_object('t',st,'l',jsonb_build_array('introduction-to-functional-health','how-nutrition-training-gut-recovery-and-nervous-system-work-together','feedback-and-self-tracking','your-unique-terrain-roadmap','signals-create-adaptation','the-power-of-compounding','the-power-of-habits','biological-recovery','what-a-personal-programme-adds'),'o','[]'::jsonb),
   jsonb_build_object('t',fue,'l',jsonb_build_array('protein-at-every-meal-and-why-it-matters','complex-or-refined-carbs-why-it-matters','fuel-and-cellular-machinery','nutrient-dense-foods','micronutrient-tracking','micronutrients-and-hormones','fuel-the-adaptation','refuel-training-signal'),'o',jsonb_build_array('fuel-the-adaptation','refuel-training-signal')),
   jsonb_build_object('t',eng,'l',jsonb_build_array('build-your-engine','build-your-aerobic-base','raise-your-aerobic-ceiling','hiit-work-recover-repeat','zone-2-cardio','zones-4-and-5','hiit'),'o',jsonb_build_array('zone-2-cardio','zones-4-and-5','hiit')),
   jsonb_build_object('t',mus,'l',jsonb_build_array('build-a-stronger-more-capable-body','make-your-training-work-better','exercise-snacks-small-signals-that-add-up','strength-is-more-than-muscle-size','micro-workouts-exercise-snacks','eccentric-training','nervous-system-and-muscle-recruitment'),'o',jsonb_build_array('micro-workouts-exercise-snacks','eccentric-training','nervous-system-and-muscle-recruitment')),
   jsonb_build_object('t',sl,'l',jsonb_build_array('light-sets-your-body-clock','caffeine-and-your-sleep','the-3-2-1-rule','your-evening-routine','nsdr-explained','morning-wake-up-routine','biological-recovery'),'o','[]'::jsonb),
   jsonb_build_object('t',ca,'l',jsonb_build_array('breathe-the-time-you-give-yourself','three-good-things','connection-is-health','the-habit-of-writing','breathing-exercises','recovery-in-three-parts'),'o','[]'::jsonb));

  for t in select * from jsonb_array_elements(spec) loop
    for i in 1..jsonb_array_length(t->'l') loop
      select id into nid from kb_nodes where slug=(t->'l'->>(i-1)) and space='patient_resources' and status='published';
      get diagnostics cnt = row_count;
      if (select count(*) from kb_nodes where slug=(t->'l'->>(i-1)) and space='patient_resources' and status='published')<>1 then
        raise exception 'node not unique/found: %', t->'l'->>(i-1); end if;
      update library_track_lessons set position=i, node_id=nid, phase_label=null,
         role=case when (t->'o') ? (t->'l'->>(i-1)) then 'optional' else null end, is_required=false
       where track_id=(t->>'t')::uuid and content_slug=(t->'l'->>(i-1));
      get diagnostics cnt = row_count;
      if cnt=0 then
        insert into library_track_lessons(track_id,position,content_slug,node_id,phase_label,role,is_required)
        values ((t->>'t')::uuid,i,t->'l'->>(i-1),nid,null,case when (t->'o') ? (t->'l'->>(i-1)) then 'optional' else null end,false);
      end if;
    end loop;
    select count(*) into got from library_track_lessons where track_id=(t->>'t')::uuid;
    if got<>jsonb_array_length(t->'l') then raise exception 'count mismatch % % vs %', t->>'t', got, jsonb_array_length(t->'l'); end if;
    if exists (select 1 from library_track_lessons l left join kb_nodes n on n.id=l.node_id where l.track_id=(t->>'t')::uuid and (n.id is null or n.status<>'published' or n.slug<>l.content_slug or l.position>100)) then
      raise exception 'unresolved lesson in %', t->>'t'; end if;
  end loop;
  if (select count(*) from library_track_lessons where track_id=sta)<>3 then raise exception 'stamina lessons changed'; end if;
  --DRYEND
end $$;
