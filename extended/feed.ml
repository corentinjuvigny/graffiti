open Eliom_content
open Eliom_lib
open Html5.F
open Server

let static_dir =
  match Eliom_config.get_config () with
    | [Simplexmlparser.Element ("staticdir", [], [Simplexmlparser.PCData dir])] ->
        dir
    | [] ->
      raise (Ocsigen_extensions.Error_in_config_file
               ("staticdir must be configured"))
    | _ ->
      raise (Ocsigen_extensions.Error_in_config_file
               ("Unexpected content inside graffiti config"))

let image_dir name =
  let dir = static_dir ^ "/graffiti_saved/" ^ (Url.encode name) in
  (try_lwt Lwt_unix.mkdir dir 0o777 with
    | _ -> debug ("could not create the directory "^dir); Lwt.return ()) >|=
  (fun () -> dir)

let make_filename name number =
  image_dir name >|= ( fun dir -> (dir ^ "/" ^ (string_of_int number) ^ ".png") )

let save image name number =
  lwt file_name = make_filename name number in
  lwt out_chan = Lwt_io.open_file ~mode:Lwt_io.output file_name in
  Lwt_io.write out_chan image

let image_info_table = Ocsipersist.open_table "image_info_table"

let save_image username =
  let now = CalendarLib.Calendar.now () in
  lwt number,_,list =
    try_lwt Ocsipersist.find image_info_table username with
      | Not_found -> Lwt.return (0,now,[])
      | e -> Lwt.fail e
  in
  lwt () = Ocsipersist.add image_info_table
    username (number+1,now,(number,now)::list) in
  let (_,image_string) = Hashtbl.find graffiti_info username in
  save (image_string ()) username number

let save_image_box =
  let save_service_reference =
    Eliom_reference.eref ~scope:Eliom_common.session_group None in
  fun name ->
  lwt save_image_service =
    match_lwt Eliom_reference.get save_service_reference with
      | None ->
	let service = Eliom_output.Action.register_post_coservice'
	  ~scope:Eliom_common.session_group
	  ~post_params:Eliom_parameter.unit
	  (fun () () -> save_image name) in
	lwt () = Eliom_reference.set save_service_reference (Some service) in
	Lwt.return service
      | Some service -> Lwt.return service
  in
  Lwt.return (
    Html5.D.post_form save_image_service
      (fun _ ->
	[p [Html5.D.string_input
               ~input_type:`Submit ~value:"save" ()]]) ())

let feed_service = Eliom_service.service ~path:["feed"]
  ~get_params:(Eliom_parameter.string "name") ()

let local_filename name number =
  ["graffiti_saved"; Url.encode name ; (string_of_int number) ^ ".png"]

let rec entries name list = function
  | 0 -> []
  | len ->
    match list with
      | [] -> []
      | (n,saved)::q ->
	let title = Atom_feed.plain
	  ("graffiti " ^ name ^ " " ^ (string_of_int n)) in
	let uri =
	  Html5.D.make_uri ~absolute:true
	    ~service:(Eliom_service.static_dir ())
	    (local_filename name n)
	in
	let entry =
	  Atom_feed.entry ~title ~id:uri ~updated:saved
            [Atom_feed.xhtmlC [ Xhtml.F.img ~src:uri ~alt:"image" ()]] in
	entry::(entries name q (len - 1))

let feed name () =
  let id = Html5.D.make_uri ~absolute:true
    ~service:feed_service name in
  let title = Atom_feed.plain ("nice drawings of " ^ name) in
  try_lwt
    Ocsipersist.find image_info_table name >|=
      (fun (number,updated,list) ->
	Atom_feed.feed ~id ~updated ~title (entries name list 10))
  with
    | Not_found ->
      let now = CalendarLib.Calendar.now () in
      Lwt.return (Atom_feed.feed ~id ~updated:now ~title [])
    | e -> Lwt.fail e

let feed name () =
  let id = Html5.D.make_uri ~absolute:true ~service:feed_service name in
  let title = Atom_feed.plain ("nice drawings of " ^ name) in
  Lwt.catch
    (fun () -> Ocsipersist.find image_info_table name >|=
	(fun (number,updated,list) -> Atom_feed.feed ~id ~updated ~title (entries name list 10)))
    ( function Not_found ->
      let now = CalendarLib.Calendar.now () in
      Lwt.return (Atom_feed.feed ~id ~updated:now ~title [])
      | e -> Lwt.fail e )

let () = Eliom_atom.Reg.register
  ~service:feed_service feed
