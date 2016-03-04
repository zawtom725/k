open Def
open Constants
open Constants.K
open Prelude

let split_config (config: k) : k * k list =
  match get_thread_set config with
  | [Map(sort,lbl,thread_set)] ->
  (let (first_thread_id,first_thread) = try KMap.choose thread_set with Not_found -> ([Bottom], [Bottom]) in
  let first_other_threads = KMap.remove first_thread_id thread_set in
  let first_global = set_thread_set config [ThreadLocal] in
  let first_other_thread_ids, _ = List.split(KMap.bindings first_other_threads) in
  [Thread(first_global,first_thread_id,first_thread,[Map(sort,lbl,first_other_threads)])], first_thread_id :: first_other_thread_ids)
  | _ -> failwith "split_config"

let plug_config (config: k) : k =
  match config with [Thread(global,thread_id,thread,[Map(sort,lbl,threads)])] ->
  let thread_set = [Map(sort,lbl,(KMap.remove [Bottom] (KMap.add thread_id thread threads)))] in
  set_thread_set global thread_set

let context_switch (config: k) (thread_id: k) : k = match config with
  [Thread(global,old_thread_id,old_thread,[Map(sort,lbl,other_threads)])] ->
  if (K.compare old_thread_id thread_id) = 0 then config else
  [Thread(global,thread_id,(KMap.find thread_id other_threads),[Map(sort,lbl,(KMap.remove thread_id (KMap.add old_thread_id old_thread other_threads)))])]

let rec take_steps (hint: klabel option) (active_threads: k list) (config: k) (depth: int) (n: int) (last_resort: bool) : k * int =
  if n = depth then (
    config,n
  ) else (
    match active_threads with
    | thread :: other_active_threads ->
    let active_config = context_switch config thread in
      match (try Some (step active_config hint) with Stuck _ -> None) with
      | Some (([Thread(_,thread_id,_,[Map(_,_,other_threads)])] as config),hint) -> (
        take_steps hint (thread_id :: other_active_threads) config depth (n+1) false
      )
      | None -> (
        match active_config with [Thread(_,thread_id,_,[Map(_,_,other_threads)])] ->
        if other_active_threads = [] then (
          if last_resort || KMap.cardinal other_threads = 0 then (
            active_config,n
          ) else (
            let (other_thread_ids,_) = List.split(KMap.bindings other_threads) in
            take_steps None (thread_id :: other_thread_ids) active_config depth n true
          )
        ) else (
          take_steps None other_active_threads active_config depth n last_resort
        )
      )
  )
          

let run (config: k) (depth: int) : k * int =
  let first_config, first_thread_ids = split_config config in
  let last_config,n = take_steps None first_thread_ids first_config depth 0 false in
  (plug_config last_config, n)
