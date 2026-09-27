REPORT zdocumizer_dev.

************************************************************************
* consiness Documizer - ABAP package / developer documentation
*
* The input is a start point: either a package - from there all
* subpackages are determined recursively - or a single object such as a
* report, class, function module, table, view or CDS view. The objects
* are read and arranged into chapters.
*
* Chapter model, interfaces, XML renderer and parser are identical to
* ZDOCUMIZER_IMG - the price for keeping every report runnable after a
* copy/paste into SE38. In the target design they live as global classes
* in ZCONS_DOCUMIZER_CORE.
*
* Standard interfaces used:
*   CL_PAK_PACKAGE_QUERIES=>GET_ALL_SUBPACKAGES        packages recursively
*   CL_PAK_PACKAGE_QUERIES=>GET_DEV_OBJECT_TADIR_KEYS  objects per package
*   RS_EU_CROSSREF                                     where-used list
*   DOCU_GET                                           object documentation
*   DD03L, SEOCOMPO, FUPARAREF                         detail information
*
* Autor     Christian Gathmann, consiness GmbH & Co. KG
*           gathmann@consiness.de
*
* Copyright 2026 consiness GmbH & Co. KG
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
************************************************************************

CLASS lcl_chapter  DEFINITION DEFERRED.
CLASS lcl_object   DEFINITION DEFERRED.
CLASS lcl_document DEFINITION DEFERRED.

*----------------------------------------------------------------------*
* lcl_t - texts of the document itself
*
* Everything that ends up in the document follows the output language the
* user selected, not the logon language: headings, table columns, notes.
* A document requested in English must not carry German column headers.
*
* Only German and English are provided. Any other output language falls
* back to English, which is the maintenance language of the SAP standard.
*----------------------------------------------------------------------*
CLASS lcl_t DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS set_lang IMPORTING iv_langu TYPE sy-langu.
    CLASS-METHODS t IMPORTING d         TYPE string
                              e         TYPE string
                    RETURNING VALUE(rv) TYPE string.
    CLASS-METHODS ui IMPORTING d         TYPE string
                               e         TYPE string
                     RETURNING VALUE(rv) TYPE string.
  PRIVATE SECTION.
    CLASS-DATA gv_de TYPE abap_bool.
ENDCLASS.

CLASS lcl_t IMPLEMENTATION.
  METHOD set_lang.
    gv_de = boolc( iv_langu = 'D' ).
  ENDMETHOD.
  METHOD t.
    IF gv_de = abap_true.
      rv = d.
    ELSE.
      rv = e.
    ENDIF.
  ENDMETHOD.
  METHOD ui.
*   The run protocol on screen belongs to whoever started the report, so
*   it follows the logon language - unlike the document, which follows
*   the output language.
    IF sy-langu = 'D'.
      rv = d.
    ELSE.
      rv = e.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

*----------------------------------------------------------------------*
* Model types
*----------------------------------------------------------------------*
TYPES: BEGIN OF ty_field,
         name     TYPE string,
         rollname TYPE string,
         keyflag  TYPE abap_bool,
       END OF ty_field.
TYPES ty_fields TYPE STANDARD TABLE OF ty_field WITH EMPTY KEY.

TYPES: BEGIN OF ty_cell,
         name  TYPE string,
         value TYPE string,
       END OF ty_cell.
TYPES ty_cells TYPE STANDARD TABLE OF ty_cell WITH EMPTY KEY.

TYPES: BEGIN OF ty_row,
         cells TYPE ty_cells,
       END OF ty_row.
TYPES ty_rows TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.

TYPES: BEGIN OF ty_reference,
         activity TYPE string,   " here: object type
         docu_id  TYPE string,   " here: author
         tcode    TYPE string,   " here: package
       END OF ty_reference.

* The definition of an object, as opposed to its description. Everything
* above this line serves the reader; what follows serves the reimport
* into another system and is therefore not translated and not formatted:
* DDIC field names as they stand, values unchanged.
*
* Deliberately generic - name/value instead of one structure per object
* type. Renderer and parser stay free of type knowledge, and a new object
* type costs one method in the collector and one in the importer, not a
* change to the format.
TYPES: BEGIN OF ty_attr,
         name  TYPE string,
         value TYPE string,
       END OF ty_attr.
TYPES ty_attrs TYPE STANDARD TABLE OF ty_attr WITH EMPTY KEY.

* A repeating part of a definition: the fields of a table, the fixed
* values of a domain, the parameters of a function module. TAG says which.
*
* SRC carries source belonging to that one row - a function group has an
* include and a body per function module, and one source per definition
* would not be enough. It has to be an element of its own, never an
* attribute: XML normalises line breaks inside an attribute value away.
TYPES: BEGIN OF ty_defrow,
         tag   TYPE string,
         attrs TYPE ty_attrs,
         src   TYPE string,
       END OF ty_defrow.
TYPES ty_defrows TYPE STANDARD TABLE OF ty_defrow WITH EMPTY KEY.

* Source as the ABAP statements want it: fixed-length lines.
TYPES ty_code TYPE STANDARD TABLE OF char255 WITH EMPTY KEY.

* A repository object the report can document. TYPE is the TADIR object
* type, plus the pseudo type FUNC for a single function module - that one
* has no TADIR entry of its own, it belongs to its function group.
TYPES: BEGIN OF ty_objref,
         type TYPE trobjtype,
         name TYPE sobj_name,
         kind TYPE string,
         deep TYPE abap_bool,   " references of this one were followed
       END OF ty_objref.
TYPES ty_objrefs TYPE STANDARD TABLE OF ty_objref WITH EMPTY KEY.
TYPES ty_names   TYPE STANDARD TABLE OF sobj_name WITH EMPTY KEY.

* A line of source at a place of use. With the full-source option every
* line is collected and HIT marks the ones the object appears in;
* otherwise only the hits are collected and HIT is always set.
 TYPES: BEGIN OF ty_hit,
         line TYPE i,
         text TYPE string,
         hit  TYPE abap_bool,
       END OF ty_hit.
 TYPES ty_hits TYPE STANDARD TABLE OF ty_hit WITH EMPTY KEY.

* Entry point types offered on the selection screen.
*
* Both components carry a data element on purpose. F4IF_INT_TABLE_VALUE_REQUEST
* derives the column description from the value table itself, and it can only
* do that when every field points to the dictionary. A plain C field or a
* string ends in ASSIGN_CASTING_ILLEGAL_CAST inside the function module.
TYPES: BEGIN OF ty_stype,
         code TYPE char2,
         text TYPE char40,
       END OF ty_stype.
TYPES ty_stypes TYPE STANDARD TABLE OF ty_stype WITH EMPTY KEY.

TYPES: BEGIN OF ty_meta,
         version    TYPE string,
         doc_type   TYPE string,
         system     TYPE string,
         client     TYPE string,
         created_by TYPE string,
         created_at TYPE string,
         language   TYPE string,
         truncated  TYPE abap_bool,
         node_limit TYPE i,
         node_total TYPE i,
         src_trunc  TYPE abap_bool,
         src_limit  TYPE i,
       END OF ty_meta.

*   Eine Paketregel: das Paket, in dem ein Objekt im Quellsystem lag,
*   und das Paket, in dem es hier landen soll.
TYPES: BEGIN OF ty_packmap,
         from TYPE devclass,
         to   TYPE devclass,
       END OF ty_packmap.
TYPES ty_packmaps TYPE STANDARD TABLE OF ty_packmap WITH EMPTY KEY.

* Objekt-Umbenennung: je importierbarem Kundenobjekt eine Zeile. Der
* Benutzer kann in einem editierbaren Grid Zielname und Zielpaket
* ueberschreiben; der neue Name wird danach in der ganzen Payload
* angewandt, bevor der Import laeuft.
TYPES: BEGIN OF ty_renrow,
         kind    TYPE string,
         oldname TYPE string,
         newname TYPE string,
         oldpack TYPE devclass,
         newpack TYPE devclass,
       END OF ty_renrow.
TYPES ty_renrows TYPE STANDARD TABLE OF ty_renrow WITH EMPTY KEY.

DATA gt_ren      TYPE ty_renrows.
DATA go_ren_dock TYPE REF TO cl_gui_docking_container.
DATA go_ren_grid TYPE REF TO cl_gui_alv_grid.

TYPES ty_chapters TYPE STANDARD TABLE OF REF TO lcl_chapter WITH EMPTY KEY.
TYPES ty_objects  TYPE STANDARD TABLE OF REF TO lcl_object  WITH EMPTY KEY.

* Run protocol of the import: one line per object, in the order in which
* it was worked on.
TYPES: BEGIN OF ty_implog_row,
         kind   TYPE string,
         name   TYPE string,
         action TYPE string,
         text   TYPE string,
       END OF ty_implog_row.
TYPES ty_implog TYPE STANDARD TABLE OF ty_implog_row WITH EMPTY KEY.

* Work list of the import. SEQ puts the objects in the order in which
* they can be activated: what a later object refers to has to exist.
TYPES: BEGIN OF ty_impwork_row,
         seq     TYPE i,
         kind    TYPE string,
         name    TYPE string,
         chapter TYPE REF TO lcl_chapter,
       END OF ty_impwork_row.
TYPES ty_impwork TYPE STANDARD TABLE OF ty_impwork_row WITH EMPTY KEY.

CONSTANTS gc_version TYPE string VALUE '1.1'.

*----------------------------------------------------------------------*
* lcl_attr - a DDIC structure as name/value pairs, and back
*
* Export and import work on the same structures: what DDIF_TABL_GET
* hands out is what DDIF_TABL_PUT takes in. Rather than listing the
* fields of DD02V, DD03P and their kin - and keeping that list in step
* with two SAP releases - the structure is walked at runtime. A field
* added by SAP travels along without a change here.
*
* Initial fields are left out. The importer starts from an initial
* structure, so an absent field means the same thing on both sides, and
* the document stays readable.
*----------------------------------------------------------------------*
*----------------------------------------------------------------------*
* Verhaltensdefinition, Service-Definition und Metadata Extension haengen
* alle am generischen Workbench-Objektoperator. Die beiden Zuordnungen
* dorthin stehen hier, weil sie der Sammler und der Importer brauchen -
* und der Importer steht weiter oben.
*----------------------------------------------------------------------*
*
* Alles hier wird dynamisch gerufen. Der Objektoperator, sein
* Datenmodell und die Datenklassen der Fiori-Schichten gibt es erst ab
* SAP_BASIS 7.5x; ein statischer Verweis darauf liesse den Report auf
* einem R/3-System mit 7.40 gar nicht erst uebersetzen. Fehlt eine Klasse
* zur Laufzeit, liefern die Methoden nichts - der Aufrufer sieht dann
* "nicht vorhanden" statt eines Abbruchs.
CLASS lcl_wb DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS data_class
      IMPORTING iv_type       TYPE trobjtype
      RETURNING VALUE(rv_cls) TYPE string.
    CLASS-METHODS obj_type
      IMPORTING iv_type        TYPE trobjtype
      RETURNING VALUE(rs_type) TYPE wbobjtype.
    CLASS-METHODS is_source
      IMPORTING iv_type         TYPE clike
      RETURNING VALUE(rv_flag)  TYPE abap_bool.
    CLASS-METHODS operator
      IMPORTING iv_type      TYPE trobjtype
                iv_name      TYPE clike
                iv_corr      TYPE trkorr OPTIONAL
      RETURNING VALUE(ro_op) TYPE REF TO object
      RAISING   cx_static_check.
    CLASS-METHODS exists
      IMPORTING iv_type        TYPE trobjtype
                iv_name        TYPE clike
      RETURNING VALUE(rv_flag) TYPE abap_bool.
    CLASS-METHODS read
      IMPORTING iv_type        TYPE trobjtype
                iv_name        TYPE clike
      RETURNING VALUE(ro_data) TYPE REF TO object.
    CLASS-METHODS description
      IMPORTING io_data        TYPE REF TO object
      RETURNING VALUE(rv_text) TYPE string.
    CLASS-METHODS content
      IMPORTING io_data       TYPE REF TO object
      RETURNING VALUE(rv_src) TYPE string.
    CLASS-METHODS all_data
      IMPORTING io_data TYPE REF TO object
      CHANGING  cs_data TYPE any.
    CLASS-METHODS new_data
      IMPORTING iv_class       TYPE clike
                iv_name        TYPE clike
                iv_desc        TYPE string
      RETURNING VALUE(ro_data) TYPE REF TO object
      RAISING   cx_static_check.
    CLASS-METHODS set_source
      IMPORTING io_data   TYPE REF TO object
                iv_source TYPE string
      RAISING   cx_static_check.
    CLASS-METHODS set_content
      IMPORTING io_data    TYPE REF TO object
                is_content TYPE any
      RAISING   cx_static_check.
    CLASS-METHODS save
      IMPORTING io_op      TYPE REF TO object
                io_data    TYPE REF TO object
                iv_update  TYPE abap_bool
                iv_package TYPE devclass
      RAISING   cx_static_check.
    CLASS-METHODS activate
      IMPORTING io_op TYPE REF TO object
      RAISING   cx_static_check.
    CLASS-METHODS srvb_data
      IMPORTING iv_type        TYPE string
      RETURNING VALUE(rr_data) TYPE REF TO data.
    CLASS-METHODS comp
      IMPORTING is_data         TYPE any
                iv_path         TYPE string
      RETURNING VALUE(rv_value) TYPE string.
    CLASS-METHODS set_comp
      IMPORTING iv_path  TYPE string
                iv_value TYPE any
      CHANGING  cs_data  TYPE any.
  PRIVATE SECTION.
    CLASS-METHODS selection
      IMPORTING iv_const   TYPE string
      RETURNING VALUE(rr)  TYPE REF TO data.
ENDCLASS.

CLASS lcl_wb IMPLEMENTATION.

  METHOD selection.
*   Die Auswahlkonstanten liegen in einem Interface, das es auf alten
*   Staenden nicht gibt - also dynamisch gelesen, in ihrem eigenen Typ.
    FIELD-SYMBOLS <lv_c> TYPE any.
    FIELD-SYMBOLS <lv_v> TYPE any.
    DATA lv_name TYPE string.
    lv_name = |IF_WB_OBJECT_DATA_SELECTION_CO=>{ iv_const }|.
    ASSIGN (lv_name) TO <lv_c>.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    CREATE DATA rr LIKE <lv_c>.
    ASSIGN rr->* TO <lv_v>.
    <lv_v> = <lv_c>.
  ENDMETHOD.

  METHOD operator.
    DATA lv_key TYPE seu_objkey.
    DATA(ls_type) = obj_type( iv_type ).
    IF ls_type-objtype_tr IS INITIAL.
      RETURN.
    ENDIF.
    lv_key = iv_name.
    CALL METHOD ('CL_WB_OBJECT_OPERATOR_FACTORY')=>('CREATE_OBJECT_OPERATOR')
      EXPORTING object_type       = ls_type
                object_key        = lv_key
                transport_request = iv_corr
      RECEIVING result            = ro_op.
  ENDMETHOD.

  METHOD exists.
*   Aktiv heisst: der Operator laedt es. Ein Katalogeintrag allein sagt
*   bei diesen Arten nichts.
    TRY.
        DATA(lo_op) = operator( iv_type = iv_type iv_name = iv_name ).
        IF lo_op IS BOUND.
          CALL METHOD lo_op->('IF_WB_OBJECT_OPERATOR~CHECK_EXISTENCE')
            RECEIVING r_result = rv_flag.
        ENDIF.
      CATCH cx_root.
        CLEAR rv_flag.
    ENDTRY.
  ENDMETHOD.

  METHOD read.
*   eo_object_data ist ein Ausgabeparameter mit Interface-Typ. Dort
*   verlangt der dynamische Aufruf genau diesen Typ - eine REF TO object
*   lehnt er mit "Falscher Typ fuer Parameter" ab. Deshalb erst in eine
*   zur Laufzeit typisierte Referenz, dann umkopieren.
    FIELD-SYMBOLS <lv_sel> TYPE any.
    FIELD-SYMBOLS <lo_dm>  TYPE any.
    DATA lr_dm TYPE REF TO data.
    TRY.
        DATA(lo_op) = operator( iv_type = iv_type iv_name = iv_name ).
        DATA(lr_sel) = selection( `C_ALL_DATA` ).
        IF lo_op IS NOT BOUND OR lr_sel IS NOT BOUND.
          RETURN.
        ENDIF.
        ASSIGN lr_sel->* TO <lv_sel>.
        CREATE DATA lr_dm TYPE REF TO ('IF_WB_OBJECT_DATA_MODEL').
        ASSIGN lr_dm->* TO <lo_dm>.
        CALL METHOD lo_op->('IF_WB_OBJECT_OPERATOR~READ')
          EXPORTING version        = 'A'
                    data_selection = <lv_sel>
          IMPORTING eo_object_data = <lo_dm>.
        ro_data = <lo_dm>.
      CATCH cx_root.
        CLEAR ro_data.
    ENDTRY.
  ENDMETHOD.

  METHOD description.
    TRY.
        CALL METHOD io_data->('IF_WB_OBJECT_DATA_MODEL~GET_DESCRIPTION')
          RECEIVING p_description = rv_text.
      CATCH cx_root.
        CLEAR rv_text.
    ENDTRY.
  ENDMETHOD.

  METHOD content.
    FIELD-SYMBOLS <lv_sel> TYPE any.
    TRY.
        DATA(lr_sel) = selection( `C_DATA_CONTENT` ).
        IF lr_sel IS NOT BOUND.
          RETURN.
        ENDIF.
        ASSIGN lr_sel->* TO <lv_sel>.
        CALL METHOD io_data->('IF_WB_OBJECT_DATA_MODEL~GET_SELECTED_DATA')
          EXPORTING p_data_selection = <lv_sel>
          IMPORTING p_data           = rv_src.
      CATCH cx_root.
        CLEAR rv_src.
    ENDTRY.
  ENDMETHOD.

  METHOD all_data.
    FIELD-SYMBOLS <lv_sel> TYPE any.
    TRY.
        DATA(lr_sel) = selection( `C_ALL_DATA` ).
        IF lr_sel IS NOT BOUND.
          RETURN.
        ENDIF.
        ASSIGN lr_sel->* TO <lv_sel>.
        CALL METHOD io_data->('IF_WB_OBJECT_DATA_MODEL~GET_SELECTED_DATA')
          EXPORTING p_data_selection = <lv_sel>
          IMPORTING p_data           = cs_data.
      CATCH cx_root.
        CLEAR cs_data.
    ENDTRY.
  ENDMETHOD.

  METHOD new_data.
    DATA lv_key TYPE seu_objkey.
    lv_key = iv_name.
    CREATE OBJECT ro_data TYPE (iv_class).
    CALL METHOD ro_data->('IF_WB_OBJECT_DATA_MODEL~SET_OBJECT_NAME')
      EXPORTING p_object_name = lv_key.
    CALL METHOD ro_data->('IF_WB_OBJECT_DATA_MODEL~SET_DESCRIPTION')
      EXPORTING p_description = iv_desc.
  ENDMETHOD.

  METHOD set_source.
    FIELD-SYMBOLS <lv_sel> TYPE any.
    DATA(lr_sel) = selection( `C_DATA_CONTENT` ).
    ASSIGN lr_sel->* TO <lv_sel>.
    CALL METHOD io_data->('IF_WB_OBJECT_DATA_MODEL~SET_SELECTED_DATA')
      EXPORTING p_data_selection = <lv_sel>
                p_data           = iv_source.
  ENDMETHOD.

  METHOD set_content.
    CALL METHOD io_data->('IF_WB_OBJECT_DATA_MODEL~SET_CONTENT')
      EXPORTING p_data = is_content.
  ENDMETHOD.

  METHOD save.
*   io_object_data ist als Interface-Referenz typisiert. Eine REF TO
*   object laesst sich dort auch dynamisch nicht uebergeben, deshalb
*   eine Referenz, deren Typ erst zur Laufzeit feststeht.
    DATA lr_dm TYPE REF TO data.
    FIELD-SYMBOLS <lo_dm> TYPE any.
    CREATE DATA lr_dm TYPE REF TO ('IF_WB_OBJECT_DATA_MODEL').
    ASSIGN lr_dm->* TO <lo_dm>.
    <lo_dm> ?= io_data.
    IF iv_update = abap_true.
      CALL METHOD io_op->('IF_WB_OBJECT_OPERATOR~UPDATE')
        EXPORTING io_object_data = <lo_dm>.
    ELSE.
      CALL METHOD io_op->('IF_WB_OBJECT_OPERATOR~CREATE')
        EXPORTING io_object_data = <lo_dm>
                  package        = iv_package.
    ENDIF.
  ENDMETHOD.

  METHOD activate.
    CALL METHOD io_op->('IF_WB_OBJECT_OPERATOR~ACTIVATE').
  ENDMETHOD.

  METHOD srvb_data.
*   Die Typen des Service-Bindings stehen in der Datenklasse. Ueber den
*   absoluten Typnamen entstehen sie zur Laufzeit.
    DATA lv_tname TYPE string.
    lv_tname = |\\CLASS=CL_SRVB_OBJECT_DATA\\TYPE={ iv_type }|.
    TRY.
        CREATE DATA rr_data TYPE (lv_tname).
      CATCH cx_root.
        CLEAR rr_data.
    ENDTRY.
  ENDMETHOD.

  METHOD comp.
*   Pfad wie CONTENT-BIND_TYPE, Stufe fuer Stufe ueber die Komponenten.
    FIELD-SYMBOLS <lv_c> TYPE any.
    ASSIGN is_data TO <lv_c>.
    SPLIT iv_path AT '-' INTO TABLE DATA(lt_step).
    LOOP AT lt_step INTO DATA(lv_step).
      ASSIGN COMPONENT lv_step OF STRUCTURE <lv_c> TO <lv_c>.
      IF sy-subrc <> 0.
        RETURN.
      ENDIF.
    ENDLOOP.
    rv_value = <lv_c>.
  ENDMETHOD.

  METHOD set_comp.
    FIELD-SYMBOLS <lv_c> TYPE any.
    ASSIGN cs_data TO <lv_c>.
    SPLIT iv_path AT '-' INTO TABLE DATA(lt_step).
    LOOP AT lt_step INTO DATA(lv_step).
      ASSIGN COMPONENT lv_step OF STRUCTURE <lv_c> TO <lv_c>.
      IF sy-subrc <> 0.
        RETURN.
      ENDIF.
    ENDLOOP.
    <lv_c> = iv_value.
  ENDMETHOD.

  METHOD data_class.
*   Das Datenmodell je Objektart. Nur diese drei sind reine
*   Quelltextobjekte; SRVB ist eine verschachtelte Struktur und geht
*   einen eigenen Weg.
    CASE iv_type.
      WHEN 'BDEF'. rv_cls = 'CL_BLUE_SOURCE_OBJECT_DATA'.
      WHEN 'SRVD'. rv_cls = 'CL_SRVD_WB_OBJECT_DATA'.
      WHEN 'DDLX'. rv_cls = 'CL_DDLX_WB_OBJECT_DATA'.
    ENDCASE.
  ENDMETHOD.

  METHOD obj_type.
    TRY.
        CALL METHOD ('CL_WB_OBJECT_TYPE')=>('GET_GLOBAL_FROM_TRANSPORT_TYPE')
          EXPORTING  p_transport_type  = iv_type
          IMPORTING  p_global_type     = rs_type
          EXCEPTIONS no_unique_mapping = 1
                     OTHERS            = 2.
        IF sy-subrc <> 0.
          CLEAR rs_type.
        ENDIF.
      CATCH cx_root.
        CLEAR rs_type.
    ENDTRY.
  ENDMETHOD.

  METHOD is_source.
    rv_flag = boolc( iv_type = 'BDEF' OR iv_type = 'SRVD' OR iv_type = 'DDLX' ).
  ENDMETHOD.

ENDCLASS.

CLASS lcl_attr DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS from_struct
      IMPORTING is_data         TYPE any
      RETURNING VALUE(rt_attrs) TYPE ty_attrs.
    CLASS-METHODS to_struct
      IMPORTING it_attrs TYPE ty_attrs
      CHANGING  cs_data  TYPE any.
    CLASS-METHODS value
      IMPORTING it_attrs        TYPE ty_attrs
                iv_name         TYPE string
      RETURNING VALUE(rv_value) TYPE string.
    CLASS-METHODS enc_name
      IMPORTING iv_name        TYPE string
      RETURNING VALUE(rv_name) TYPE string.
    CLASS-METHODS dec_name
      IMPORTING iv_name        TYPE string
      RETURNING VALUE(rv_name) TYPE string.
ENDCLASS.

CLASS lcl_attr IMPLEMENTATION.

  METHOD from_struct.

    DATA(lo_type) = cl_abap_typedescr=>describe_by_data( is_data ).
    IF lo_type->kind <> cl_abap_typedescr=>kind_struct.
      RETURN.
    ENDIF.

*   get_included_view, not get_components. The latter hands back a
*   .INCLUDE as one nested component, and everything inside it would be
*   skipped by the flat-field test below - silently, and with the row
*   still counted. The DDIF interface structures are flat and never
*   showed it; RSMPE_FUNT is three includes and almost nothing else,
*   and came through with every field empty.
    LOOP AT CAST cl_abap_structdescr( lo_type )->get_included_view( )
         INTO DATA(ls_comp).
*     Only flat fields. A nested table or structure inside a DDIC
*     interface structure carries no value the PUT would read back.
      IF ls_comp-type->kind <> cl_abap_typedescr=>kind_elem.
        CONTINUE.
      ENDIF.
      ASSIGN COMPONENT ls_comp-name OF STRUCTURE is_data
             TO FIELD-SYMBOL(<lv_val>).
      IF sy-subrc <> 0 OR <lv_val> IS INITIAL.
        CONTINUE.
      ENDIF.
      DATA(lv_aname) = enc_name( ls_comp-name ).
      IF lv_aname CN 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_'.
*       Ein Zeichen, fuer das enc_name keine Marke kennt. Als
*       XML-Attributname waere der Name ungueltig und das ganze
*       Dokument unlesbar - das Feld bleibt weg.
        CONTINUE.
      ENDIF.
      APPEND VALUE ty_attr( name  = lv_aname
                            value = |{ <lv_val> }| ) TO rt_attrs.
    ENDLOOP.

  ENDMETHOD.

  METHOD enc_name.

*   Nicht jeder DDIC-Feldname ist ein gueltiger XML-Attributname.
*   RPY_DYFATC - die Dynpro-Feldliste - hat die Felder *_ENTRY und
*   2_DIMENS: ein Stern ist im Namen verboten, eine fuehrende Ziffer
*   auch. Ohne Umschrift kaeme kein Dynpro durch den Writer.
*
*   Umgeschrieben wird ueber eine feste Tabelle, nicht ueber eine
*   Codepage-Klasse: die Marken sind kleingeschrieben und kommen in
*   DDIC-Feldnamen nicht vor, also ist die Umschrift umkehrbar. Ein
*   Zeichen, das hier nicht steht, wird in from_struct gar nicht erst
*   aufgenommen - lieber ein fehlendes Feld als ein falsches.
    rv_name = iv_name.
    REPLACE ALL OCCURRENCES OF `*` IN rv_name WITH `_xas_`.
    REPLACE ALL OCCURRENCES OF `/` IN rv_name WITH `_xsl_`.
    REPLACE ALL OCCURRENCES OF `-` IN rv_name WITH `_xmi_`.
    REPLACE ALL OCCURRENCES OF `.` IN rv_name WITH `_xdt_`.

    IF rv_name IS NOT INITIAL AND rv_name(1) CA '0123456789'.
      rv_name = |_n{ rv_name }|.
    ENDIF.

  ENDMETHOD.

  METHOD dec_name.

    rv_name = iv_name.
    IF strlen( rv_name ) > 2 AND rv_name(2) = `_n`.
      rv_name = rv_name+2.
    ENDIF.
    REPLACE ALL OCCURRENCES OF `_xas_` IN rv_name WITH `*`.
    REPLACE ALL OCCURRENCES OF `_xsl_` IN rv_name WITH `/`.
    REPLACE ALL OCCURRENCES OF `_xmi_` IN rv_name WITH `-`.
    REPLACE ALL OCCURRENCES OF `_xdt_` IN rv_name WITH `.`.

  ENDMETHOD.

  METHOD to_struct.

    LOOP AT it_attrs INTO DATA(ls_attr).
      ASSIGN COMPONENT dec_name( ls_attr-name ) OF STRUCTURE cs_data
             TO FIELD-SYMBOL(<lv_val>).
*     A field the target release does not know is skipped, not fatal.
*     That is the whole point of transporting name/value pairs.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      TRY.
          <lv_val> = ls_attr-value.
        CATCH cx_root.
          CLEAR <lv_val>.
      ENDTRY.
    ENDLOOP.

  ENDMETHOD.

  METHOD value.
    READ TABLE it_attrs INTO DATA(ls_attr) WITH KEY name = iv_name.
    IF sy-subrc = 0.
      rv_value = ls_attr-value.
    ENDIF.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* lcl_object
*----------------------------------------------------------------------*
CLASS lcl_object DEFINITION.
  PUBLIC SECTION.
    METHODS constructor
      IMPORTING iv_type  TYPE string
                iv_name  TYPE string
                iv_tcode TYPE string OPTIONAL.
    METHODS add_field     IMPORTING is_field     TYPE ty_field.
    METHODS add_row       IMPORTING is_row       TYPE ty_row.
    METHODS set_row_count IMPORTING iv_row_count TYPE i.
    METHODS set_truncated IMPORTING iv_truncated TYPE abap_bool.
    METHODS set_note      IMPORTING iv_note      TYPE string.
    METHODS get_type      RETURNING VALUE(rv_type)      TYPE string.
    METHODS get_name      RETURNING VALUE(rv_name)      TYPE string.
    METHODS get_tcode     RETURNING VALUE(rv_tcode)     TYPE string.
    METHODS get_note      RETURNING VALUE(rv_note)      TYPE string.
    METHODS get_fields    RETURNING VALUE(rt_fields)    TYPE ty_fields.
    METHODS get_rows      RETURNING VALUE(rt_rows)      TYPE ty_rows.
    METHODS get_row_count RETURNING VALUE(rv_row_count) TYPE i.
    METHODS get_truncated RETURNING VALUE(rv_truncated) TYPE abap_bool.
  PRIVATE SECTION.
    DATA mv_type      TYPE string.
    DATA mv_name      TYPE string.
    DATA mv_tcode     TYPE string.
    DATA mv_note      TYPE string.
    DATA mt_fields    TYPE ty_fields.
    DATA mt_rows      TYPE ty_rows.
    DATA mv_row_count TYPE i.
    DATA mv_truncated TYPE abap_bool.
ENDCLASS.

CLASS lcl_object IMPLEMENTATION.
  METHOD constructor.
    mv_type  = iv_type.
    mv_name  = iv_name.
    mv_tcode = iv_tcode.
  ENDMETHOD.
  METHOD add_field.
    APPEND is_field TO mt_fields.
  ENDMETHOD.
  METHOD add_row.
    APPEND is_row TO mt_rows.
  ENDMETHOD.
  METHOD set_row_count.
    mv_row_count = iv_row_count.
  ENDMETHOD.
  METHOD set_truncated.
    mv_truncated = iv_truncated.
  ENDMETHOD.
  METHOD set_note.
    mv_note = iv_note.
  ENDMETHOD.
  METHOD get_type.
    rv_type = mv_type.
  ENDMETHOD.
  METHOD get_name.
    rv_name = mv_name.
  ENDMETHOD.
  METHOD get_tcode.
    rv_tcode = mv_tcode.
  ENDMETHOD.
  METHOD get_note.
    rv_note = mv_note.
  ENDMETHOD.
  METHOD get_fields.
    rt_fields = mt_fields.
  ENDMETHOD.
  METHOD get_rows.
    rt_rows = mt_rows.
  ENDMETHOD.
  METHOD get_row_count.
    rv_row_count = mv_row_count.
  ENDMETHOD.
  METHOD get_truncated.
    rv_truncated = mv_truncated.
  ENDMETHOD.
ENDCLASS.

*----------------------------------------------------------------------*
* lcl_chapter
*----------------------------------------------------------------------*
CLASS lcl_chapter DEFINITION.
  PUBLIC SECTION.
    METHODS constructor
      IMPORTING iv_id    TYPE string
                iv_level TYPE i
                iv_type  TYPE string
                iv_title TYPE string.
    METHODS add_child         IMPORTING io_child     TYPE REF TO lcl_chapter.
    METHODS add_object        IMPORTING io_object    TYPE REF TO lcl_object.
    METHODS set_reference     IMPORTING is_reference TYPE ty_reference.
    METHODS set_documentation IMPORTING iv_text      TYPE string.
    METHODS set_source        IMPORTING iv_source    TYPE string.
    METHODS set_doclang       IMPORTING iv_lang      TYPE string.
    METHODS get_doclang       RETURNING VALUE(rv_lang) TYPE string.
    METHODS get_source        RETURNING VALUE(rv_source) TYPE string.
    METHODS set_title         IMPORTING iv_title     TYPE string.
    METHODS get_id            RETURNING VALUE(rv_id)        TYPE string.
    METHODS get_level         RETURNING VALUE(rv_level)     TYPE i.
    METHODS get_type          RETURNING VALUE(rv_type)      TYPE string.
    METHODS get_title         RETURNING VALUE(rv_title)     TYPE string.
    METHODS get_children      RETURNING VALUE(rt_children)  TYPE ty_chapters.
    METHODS get_objects       RETURNING VALUE(rt_objects)   TYPE ty_objects.
    METHODS get_reference     RETURNING VALUE(rs_reference) TYPE ty_reference.
    METHODS get_documentation RETURNING VALUE(rv_text)      TYPE string.
    METHODS has_reference     RETURNING VALUE(rv_flag)      TYPE abap_bool.

*   Definition for the reimport. KIND is the object type the importer
*   dispatches on; empty means the chapter carries description only.
    METHODS set_definition
      IMPORTING iv_kind TYPE string
                it_head TYPE ty_attrs OPTIONAL.
    METHODS add_defrow     IMPORTING is_row TYPE ty_defrow.
*   The source belonging to the definition. Separate from the chapter
*   source, which the reader sees and which P_MAXSRC may have cut short -
*   a truncated source is fine to read and useless to import.
    METHODS set_defsource  IMPORTING iv_source TYPE string.
    METHODS get_defsource  RETURNING VALUE(rv_source) TYPE string.
    METHODS get_defkind    RETURNING VALUE(rv_kind) TYPE string.
    METHODS get_defhead    RETURNING VALUE(rt_head) TYPE ty_attrs.
    METHODS get_defrows    RETURNING VALUE(rt_rows) TYPE ty_defrows.
    METHODS has_definition RETURNING VALUE(rv_flag) TYPE abap_bool.
  PRIVATE SECTION.
    DATA mv_id            TYPE string.
    DATA mv_level         TYPE i.
    DATA mv_type          TYPE string.
    DATA mv_title         TYPE string.
    DATA ms_reference     TYPE ty_reference.
    DATA mv_documentation TYPE string.
    DATA mv_source        TYPE string.
    DATA mv_doclang       TYPE string.
    DATA mt_children      TYPE ty_chapters.
    DATA mt_objects       TYPE ty_objects.
    DATA mv_defkind       TYPE string.
    DATA mt_defhead       TYPE ty_attrs.
    DATA mt_defrows       TYPE ty_defrows.
    DATA mv_defsource     TYPE string.
ENDCLASS.

CLASS lcl_chapter IMPLEMENTATION.
  METHOD constructor.
    mv_id    = iv_id.
    mv_level = iv_level.
    mv_type  = iv_type.
    mv_title = iv_title.
  ENDMETHOD.
  METHOD add_child.
    APPEND io_child TO mt_children.
  ENDMETHOD.
  METHOD add_object.
    APPEND io_object TO mt_objects.
  ENDMETHOD.
  METHOD set_reference.
    ms_reference = is_reference.
  ENDMETHOD.
  METHOD set_documentation.
    mv_documentation = iv_text.
  ENDMETHOD.
  METHOD set_source.
    mv_source = iv_source.
  ENDMETHOD.
  METHOD set_doclang.
    mv_doclang = iv_lang.
  ENDMETHOD.
  METHOD get_doclang.
    rv_lang = mv_doclang.
  ENDMETHOD.
  METHOD get_source.
    rv_source = mv_source.
  ENDMETHOD.
  METHOD set_title.
    mv_title = iv_title.
  ENDMETHOD.
  METHOD get_id.
    rv_id = mv_id.
  ENDMETHOD.
  METHOD get_level.
    rv_level = mv_level.
  ENDMETHOD.
  METHOD get_type.
    rv_type = mv_type.
  ENDMETHOD.
  METHOD get_title.
    rv_title = mv_title.
  ENDMETHOD.
  METHOD get_children.
    rt_children = mt_children.
  ENDMETHOD.
  METHOD get_objects.
    rt_objects = mt_objects.
  ENDMETHOD.
  METHOD get_reference.
    rs_reference = ms_reference.
  ENDMETHOD.
  METHOD get_documentation.
    rv_text = mv_documentation.
  ENDMETHOD.
  METHOD has_reference.
    IF ms_reference IS INITIAL.
      rv_flag = abap_false.
    ELSE.
      rv_flag = abap_true.
    ENDIF.
  ENDMETHOD.
  METHOD set_definition.
    mv_defkind = iv_kind.
    mt_defhead = it_head.
  ENDMETHOD.
  METHOD add_defrow.
    APPEND is_row TO mt_defrows.
  ENDMETHOD.
  METHOD set_defsource.
    mv_defsource = iv_source.
  ENDMETHOD.
  METHOD get_defsource.
    rv_source = mv_defsource.
  ENDMETHOD.
  METHOD get_defkind.
    rv_kind = mv_defkind.
  ENDMETHOD.
  METHOD get_defhead.
    rt_head = mt_defhead.
  ENDMETHOD.
  METHOD get_defrows.
    rt_rows = mt_defrows.
  ENDMETHOD.
  METHOD has_definition.
    IF mv_defkind IS INITIAL.
      rv_flag = abap_false.
    ELSE.
      rv_flag = abap_true.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

*----------------------------------------------------------------------*
* lcl_document
*----------------------------------------------------------------------*
CLASS lcl_document DEFINITION.
  PUBLIC SECTION.
    METHODS set_meta     IMPORTING is_meta    TYPE ty_meta.
    METHODS add_chapter  IMPORTING io_chapter TYPE REF TO lcl_chapter.
    METHODS get_meta     RETURNING VALUE(rs_meta)     TYPE ty_meta.
    METHODS get_chapters RETURNING VALUE(rt_chapters) TYPE ty_chapters.
  PRIVATE SECTION.
    DATA ms_meta     TYPE ty_meta.
    DATA mt_chapters TYPE ty_chapters.
ENDCLASS.

CLASS lcl_document IMPLEMENTATION.
  METHOD set_meta.
    ms_meta = is_meta.
  ENDMETHOD.
  METHOD add_chapter.
    APPEND io_chapter TO mt_chapters.
  ENDMETHOD.
  METHOD get_meta.
    rs_meta = ms_meta.
  ENDMETHOD.
  METHOD get_chapters.
    rt_chapters = mt_chapters.
  ENDMETHOD.
ENDCLASS.

*----------------------------------------------------------------------*
* Interfaces
*----------------------------------------------------------------------*
INTERFACE lif_docu_collector.
  METHODS collect RETURNING VALUE(ro_document) TYPE REF TO lcl_document.
ENDINTERFACE.

INTERFACE lif_docu_renderer.
  METHODS render
    IMPORTING io_document       TYPE REF TO lcl_document
              iv_pretty         TYPE abap_bool DEFAULT abap_false
    RETURNING VALUE(rv_content) TYPE string.
ENDINTERFACE.

*----------------------------------------------------------------------*
* lcl_renderer_xml
*----------------------------------------------------------------------*
CLASS lcl_renderer_xml DEFINITION.
  PUBLIC SECTION.
    INTERFACES lif_docu_renderer.
  PRIVATE SECTION.
    DATA mo_writer TYPE REF TO if_sxml_writer.
    METHODS write_text_element IMPORTING iv_name TYPE string iv_value TYPE string.
    METHODS write_chapter      IMPORTING io_chapter TYPE REF TO lcl_chapter.
    METHODS write_object       IMPORTING io_object  TYPE REF TO lcl_object.
ENDCLASS.

CLASS lcl_renderer_xml IMPLEMENTATION.

  METHOD lif_docu_renderer~render.

    DATA lo_string_writer TYPE REF TO cl_sxml_string_writer.

    lo_string_writer = cl_sxml_string_writer=>create( type = if_sxml=>co_xt_xml10 ).
    mo_writer = lo_string_writer.

    IF iv_pretty = abap_true.
      mo_writer->set_option( option = if_sxml_writer=>co_opt_linebreaks ).
      mo_writer->set_option( option = if_sxml_writer=>co_opt_indent ).
    ENDIF.

    DATA(ls_meta) = io_document->get_meta( ).

    mo_writer->open_element( name = 'documizer' ).
    mo_writer->write_attribute( name = 'version' value = ls_meta-version ).
    mo_writer->write_attribute( name = 'type'    value = ls_meta-doc_type ).

    mo_writer->open_element( name = 'meta' ).
    write_text_element( iv_name = 'system'     iv_value = ls_meta-system ).
    write_text_element( iv_name = 'client'     iv_value = ls_meta-client ).
    write_text_element( iv_name = 'created_by' iv_value = ls_meta-created_by ).
    write_text_element( iv_name = 'created_at' iv_value = ls_meta-created_at ).
    write_text_element( iv_name = 'language'   iv_value = ls_meta-language ).
    IF ls_meta-truncated = abap_true.
      write_text_element( iv_name = 'truncated' iv_value = 'true' ).
    ELSE.
      write_text_element( iv_name = 'truncated' iv_value = 'false' ).
    ENDIF.
    write_text_element( iv_name = 'node_limit' iv_value = |{ ls_meta-node_limit }| ).
    write_text_element( iv_name = 'node_total' iv_value = |{ ls_meta-node_total }| ).
    IF ls_meta-src_trunc = abap_true.
      write_text_element( iv_name = 'src_truncated' iv_value = 'true' ).
    ELSE.
      write_text_element( iv_name = 'src_truncated' iv_value = 'false' ).
    ENDIF.
    write_text_element( iv_name = 'src_limit' iv_value = |{ ls_meta-src_limit }| ).
    mo_writer->close_element( ).

    mo_writer->open_element( name = 'chapters' ).
    LOOP AT io_document->get_chapters( ) INTO DATA(lo_chapter).
      write_chapter( lo_chapter ).
    ENDLOOP.
    mo_writer->close_element( ).

    mo_writer->close_element( ).

    rv_content = cl_abap_codepage=>convert_from( lo_string_writer->get_output( ) ).

  ENDMETHOD.

  METHOD write_text_element.
    mo_writer->open_element( name = iv_name ).
    IF iv_value IS NOT INITIAL.
      mo_writer->write_value( iv_value ).
    ENDIF.
    mo_writer->close_element( ).
  ENDMETHOD.

  METHOD write_chapter.

    mo_writer->open_element( name = 'chapter' ).
    mo_writer->write_attribute( name = 'id'    value = io_chapter->get_id( ) ).
    mo_writer->write_attribute( name = 'level' value = |{ io_chapter->get_level( ) }| ).
    mo_writer->write_attribute( name = 'type'  value = io_chapter->get_type( ) ).

    write_text_element( iv_name = 'title' iv_value = io_chapter->get_title( ) ).

    IF io_chapter->has_reference( ) = abap_true.
      DATA(ls_ref) = io_chapter->get_reference( ).
      mo_writer->open_element( name = 'reference' ).
      mo_writer->write_attribute( name = 'objtype' value = ls_ref-activity ).
      mo_writer->write_attribute( name = 'author'  value = ls_ref-docu_id ).
      mo_writer->write_attribute( name = 'package' value = ls_ref-tcode ).
      mo_writer->close_element( ).
    ENDIF.

    IF io_chapter->get_documentation( ) IS NOT INITIAL.
      mo_writer->open_element( name = 'documentation' ).
      mo_writer->write_attribute( name = 'format' value = 'ITF' ).
      mo_writer->write_attribute( name = 'lang'   value = io_chapter->get_doclang( ) ).
      mo_writer->write_value( io_chapter->get_documentation( ) ).
      mo_writer->close_element( ).
    ENDIF.

    IF io_chapter->get_source( ) IS NOT INITIAL.
      mo_writer->open_element( name = 'source' ).
      mo_writer->write_value( io_chapter->get_source( ) ).
      mo_writer->close_element( ).
    ENDIF.

    IF io_chapter->has_definition( ) = abap_true.
      mo_writer->open_element( name = 'definition' ).
      mo_writer->write_attribute( name = 'kind' value = io_chapter->get_defkind( ) ).
      LOOP AT io_chapter->get_defhead( ) INTO DATA(ls_ha).
        mo_writer->open_element( name = 'attr' ).
        mo_writer->write_attribute( name = 'name'  value = ls_ha-name ).
        mo_writer->write_attribute( name = 'value' value = ls_ha-value ).
        mo_writer->close_element( ).
      ENDLOOP.
      LOOP AT io_chapter->get_defrows( ) INTO DATA(ls_dr).
        mo_writer->open_element( name = 'row' ).
        mo_writer->write_attribute( name = 'tag' value = ls_dr-tag ).
        LOOP AT ls_dr-attrs INTO DATA(ls_ra).
          mo_writer->open_element( name = 'attr' ).
          mo_writer->write_attribute( name = 'name'  value = ls_ra-name ).
          mo_writer->write_attribute( name = 'value' value = ls_ra-value ).
          mo_writer->close_element( ).
        ENDLOOP.
        IF ls_dr-src IS NOT INITIAL.
          mo_writer->open_element( name = 'src' ).
          mo_writer->write_value( ls_dr-src ).
          mo_writer->close_element( ).
        ENDIF.
        mo_writer->close_element( ).
      ENDLOOP.
      IF io_chapter->get_defsource( ) IS NOT INITIAL.
        mo_writer->open_element( name = 'defsource' ).
        mo_writer->write_value( io_chapter->get_defsource( ) ).
        mo_writer->close_element( ).
      ENDIF.
      mo_writer->close_element( ).
    ENDIF.

    LOOP AT io_chapter->get_objects( ) INTO DATA(lo_object).
      write_object( lo_object ).
    ENDLOOP.

    LOOP AT io_chapter->get_children( ) INTO DATA(lo_child).
      write_chapter( lo_child ).
    ENDLOOP.

    mo_writer->close_element( ).

  ENDMETHOD.

  METHOD write_object.

    mo_writer->open_element( name = 'object' ).
    mo_writer->write_attribute( name = 'type' value = io_object->get_type( ) ).
    mo_writer->write_attribute( name = 'name' value = io_object->get_name( ) ).
    mo_writer->write_attribute( name = 'note' value = io_object->get_note( ) ).

    mo_writer->open_element( name = 'structure' ).
    LOOP AT io_object->get_fields( ) INTO DATA(ls_field).
      mo_writer->open_element( name = 'field' ).
      mo_writer->write_attribute( name = 'name'     value = ls_field-name ).
      mo_writer->write_attribute( name = 'rollname' value = ls_field-rollname ).
      IF ls_field-keyflag = abap_true.
        mo_writer->write_attribute( name = 'key' value = 'X' ).
      ELSE.
        mo_writer->write_attribute( name = 'key' value = '' ).
      ENDIF.
      mo_writer->close_element( ).
    ENDLOOP.
    mo_writer->close_element( ).

    mo_writer->close_element( ).

  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* lcl_parser_xml
*----------------------------------------------------------------------*
CLASS lcl_parser_xml DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS parse
      IMPORTING iv_xml             TYPE string
      RETURNING VALUE(ro_document) TYPE REF TO lcl_document.
ENDCLASS.

CLASS lcl_parser_xml IMPLEMENTATION.

  METHOD parse.

    DATA lo_reader  TYPE REF TO if_sxml_reader.
    DATA lt_stack   TYPE ty_chapters.
    DATA lo_current TYPE REF TO lcl_chapter.
    DATA lo_object  TYPE REF TO lcl_object.
    DATA ls_meta    TYPE ty_meta.
    DATA lv_target  TYPE string.

*   State of the definition element: attributes belong to the current row
*   while one is open, to the header otherwise.
    DATA lv_defkind TYPE string.
    DATA lt_defhead TYPE ty_attrs.
    DATA ls_defrow  TYPE ty_defrow.
    DATA lv_inrow   TYPE abap_bool.

    ro_document = NEW lcl_document( ).
    lo_reader   = cl_sxml_string_reader=>create( cl_abap_codepage=>convert_to( iv_xml ) ).

    DO.

      DATA(lo_node) = lo_reader->read_next_node( ).
      IF lo_node IS INITIAL.
        EXIT.
      ENDIF.

      CASE lo_node->type.

        WHEN if_sxml_node=>co_nt_element_open.

          DATA(lo_open) = CAST if_sxml_open_element( lo_node ).
          DATA(lv_name) = lo_open->qname-name.
          DATA(lt_attr) = lo_open->get_attributes( ).
          CLEAR lv_target.

          CASE lv_name.

            WHEN 'documizer'.
              LOOP AT lt_attr INTO DATA(lo_attr).
                CASE lo_attr->qname-name.
                  WHEN 'version'. ls_meta-version  = lo_attr->get_value( ).
                  WHEN 'type'.    ls_meta-doc_type = lo_attr->get_value( ).
                ENDCASE.
              ENDLOOP.

            WHEN 'system' OR 'client' OR 'created_by' OR 'created_at'
              OR 'language' OR 'truncated' OR 'node_limit' OR 'node_total'
              OR 'src_truncated' OR 'src_limit'.
              lv_target = lv_name.

            WHEN 'chapter'.
              DATA lv_id    TYPE string.
              DATA lv_level TYPE i.
              DATA lv_type  TYPE string.
              CLEAR: lv_id, lv_level, lv_type.
              LOOP AT lt_attr INTO lo_attr.
                CASE lo_attr->qname-name.
                  WHEN 'id'.    lv_id    = lo_attr->get_value( ).
                  WHEN 'level'. lv_level = lo_attr->get_value( ).
                  WHEN 'type'.  lv_type  = lo_attr->get_value( ).
                ENDCASE.
              ENDLOOP.
              DATA(lo_new) = NEW lcl_chapter( iv_id    = lv_id
                                              iv_level = lv_level
                                              iv_type  = lv_type
                                              iv_title = space ).
              IF lo_current IS BOUND.
                lo_current->add_child( lo_new ).
              ELSE.
                ro_document->add_chapter( lo_new ).
              ENDIF.
              APPEND lo_new TO lt_stack.
              lo_current = lo_new.

            WHEN 'title'.
              lv_target = 'title'.

            WHEN 'documentation'.
              lv_target = 'documentation'.
              LOOP AT lt_attr INTO lo_attr.
                IF lo_attr->qname-name = 'lang' AND lo_current IS BOUND.
                  lo_current->set_doclang( lo_attr->get_value( ) ).
                ENDIF.
              ENDLOOP.

            WHEN 'source'.
              lv_target = 'source'.

            WHEN 'defsource'.
              lv_target = 'defsource'.

            WHEN 'src'.
              lv_target = 'src'.

            WHEN 'definition'.
              CLEAR: lv_defkind, lt_defhead, ls_defrow, lv_inrow.
              LOOP AT lt_attr INTO lo_attr.
                IF lo_attr->qname-name = 'kind'.
                  lv_defkind = lo_attr->get_value( ).
                ENDIF.
              ENDLOOP.

            WHEN 'row'.
              CLEAR ls_defrow.
              lv_inrow = abap_true.
              LOOP AT lt_attr INTO lo_attr.
                IF lo_attr->qname-name = 'tag'.
                  ls_defrow-tag = lo_attr->get_value( ).
                ENDIF.
              ENDLOOP.

            WHEN 'attr'.
              DATA ls_pair TYPE ty_attr.
              CLEAR ls_pair.
              LOOP AT lt_attr INTO lo_attr.
                CASE lo_attr->qname-name.
                  WHEN 'name'.  ls_pair-name  = lo_attr->get_value( ).
                  WHEN 'value'. ls_pair-value = lo_attr->get_value( ).
                ENDCASE.
              ENDLOOP.
              IF lv_inrow = abap_true.
                APPEND ls_pair TO ls_defrow-attrs.
              ELSE.
                APPEND ls_pair TO lt_defhead.
              ENDIF.

            WHEN 'reference'.
              DATA ls_ref TYPE ty_reference.
              CLEAR ls_ref.
              LOOP AT lt_attr INTO lo_attr.
                CASE lo_attr->qname-name.
                  WHEN 'objtype'. ls_ref-activity = lo_attr->get_value( ).
                  WHEN 'author'.  ls_ref-docu_id  = lo_attr->get_value( ).
                  WHEN 'package'. ls_ref-tcode    = lo_attr->get_value( ).
                ENDCASE.
              ENDLOOP.
              IF lo_current IS BOUND.
                lo_current->set_reference( ls_ref ).
              ENDIF.

            WHEN 'object'.
              DATA lv_otype TYPE string.
              DATA lv_oname TYPE string.
              DATA lv_onote TYPE string.
              CLEAR: lv_otype, lv_oname, lv_onote.
              LOOP AT lt_attr INTO lo_attr.
                CASE lo_attr->qname-name.
                  WHEN 'type'. lv_otype = lo_attr->get_value( ).
                  WHEN 'name'. lv_oname = lo_attr->get_value( ).
                  WHEN 'note'. lv_onote = lo_attr->get_value( ).
                ENDCASE.
              ENDLOOP.
              lo_object = NEW lcl_object( iv_type = lv_otype iv_name = lv_oname ).
              lo_object->set_note( lv_onote ).
              IF lo_current IS BOUND.
                lo_current->add_object( lo_object ).
              ENDIF.

            WHEN 'field'.
              DATA ls_field TYPE ty_field.
              CLEAR ls_field.
              LOOP AT lt_attr INTO lo_attr.
                CASE lo_attr->qname-name.
                  WHEN 'name'.     ls_field-name     = lo_attr->get_value( ).
                  WHEN 'rollname'. ls_field-rollname = lo_attr->get_value( ).
                  WHEN 'key'.
                    IF lo_attr->get_value( ) = 'X'.
                      ls_field-keyflag = abap_true.
                    ENDIF.
                ENDCASE.
              ENDLOOP.
              IF lo_object IS BOUND.
                lo_object->add_field( ls_field ).
              ENDIF.

          ENDCASE.

        WHEN if_sxml_node=>co_nt_value.

          IF lv_target IS NOT INITIAL.
            DATA(lv_value) = CAST if_sxml_value_node( lo_node )->get_value( ).
            CASE lv_target.
              WHEN 'system'.     ls_meta-system     = lv_value.
              WHEN 'client'.     ls_meta-client     = lv_value.
              WHEN 'created_by'. ls_meta-created_by = lv_value.
              WHEN 'created_at'. ls_meta-created_at = lv_value.
              WHEN 'language'.   ls_meta-language   = lv_value.
              WHEN 'node_limit'. ls_meta-node_limit = CONV i( lv_value ).
              WHEN 'node_total'. ls_meta-node_total = CONV i( lv_value ).
              WHEN 'src_limit'.  ls_meta-src_limit  = CONV i( lv_value ).
              WHEN 'truncated'.
                IF lv_value = 'true'.
                  ls_meta-truncated = abap_true.
                ENDIF.
              WHEN 'src_truncated'.
                IF lv_value = 'true'.
                  ls_meta-src_trunc = abap_true.
                ENDIF.
              WHEN 'title'.
                IF lo_current IS BOUND.
                  lo_current->set_title( lv_value ).
                ENDIF.
              WHEN 'documentation'.
                IF lo_current IS BOUND.
                  lo_current->set_documentation( lv_value ).
                ENDIF.
              WHEN 'source'.
                IF lo_current IS BOUND.
                  lo_current->set_source( lv_value ).
                ENDIF.
              WHEN 'defsource'.
                IF lo_current IS BOUND.
                  lo_current->set_defsource( lv_value ).
                ENDIF.
              WHEN 'src'.
                ls_defrow-src = lv_value.
            ENDCASE.
          ENDIF.

        WHEN if_sxml_node=>co_nt_element_close.

          DATA(lo_close) = CAST if_sxml_close_element( lo_node ).

          CASE lo_close->qname-name.
            WHEN 'chapter'.
              DATA(lv_last) = lines( lt_stack ).
              IF lv_last > 0.
                DELETE lt_stack INDEX lv_last.
              ENDIF.
              lv_last = lines( lt_stack ).
              IF lv_last > 0.
                lo_current = lt_stack[ lv_last ].
              ELSE.
                CLEAR lo_current.
              ENDIF.
            WHEN 'object'.
              CLEAR lo_object.
            WHEN 'row'.
              lv_inrow = abap_false.
              IF lo_current IS BOUND.
                lo_current->add_defrow( ls_defrow ).
              ENDIF.
              CLEAR ls_defrow.
            WHEN 'definition'.
*             Set last: the rows went in one by one, kind and header
*             close the definition off.
              IF lo_current IS BOUND.
                lo_current->set_definition( iv_kind = lv_defkind
                                            it_head = lt_defhead ).
              ENDIF.
              CLEAR: lv_defkind, lt_defhead.
          ENDCASE.

          CLEAR lv_target.

      ENDCASE.

    ENDDO.

    ro_document->set_meta( ls_meta ).

  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* lcl_importer - the other direction
*
* Reads a document that was written in another system and creates the
* objects it defines. Everything the DDIC needs travels in the same
* structures the DDIF_*_PUT function modules expect, so the importer
* only has to fill them and hand them over.
*
* The authority check of the called APIs stays switched on. They test
* S_DEVELOP for the object and the package and refuse when the rights
* are missing - which is exactly what should happen. Switching it off
* would let this report create repository objects for someone who is
* not allowed to create them by hand.
*
* Two rules run through the whole class:
*   - Nothing is written in a test run. The caller has to switch that
*     off, and every step reports what it would have done.
*   - An object that already exists is left alone unless overwriting was
*     asked for. A documentation tool must not quietly replace a table.
*
* The order is fixed: domains, then data elements, then tables, then
* programs. A table whose data elements do not exist yet cannot be
* activated, and sorting the work is cheaper than retrying it.
*----------------------------------------------------------------------*
CLASS lcl_importer DEFINITION.
  PUBLIC SECTION.
    METHODS constructor
      IMPORTING iv_test TYPE abap_bool
                iv_over TYPE abap_bool
                iv_act  TYPE abap_bool
                iv_pack TYPE devclass
                iv_tr   TYPE trkorr
                iv_keep TYPE abap_bool DEFAULT abap_false
                it_map  TYPE ty_packmaps OPTIONAL.
    METHODS run IMPORTING io_document TYPE REF TO lcl_document.
    METHODS get_log RETURNING VALUE(rt_log) TYPE ty_implog.
*   Ermittelt ohne zu schreiben die Arbeitsliste (Objektart + Name) eines
*   Dokuments - fuer die Umbenennungs-Vorschau.
    METHODS plan
      IMPORTING io_document    TYPE REF TO lcl_document
      RETURNING VALUE(rt_work) TYPE ty_impwork.
*   Uebergibt die Umbenennungstabelle; set_pack liest daraus je Objekt
*   das Zielpaket.
    METHODS set_renames IMPORTING it_ren TYPE ty_renrows.
  PRIVATE SECTION.
    DATA mt_ren TYPE ty_renrows.
    METHODS obj_name
      IMPORTING io_chapter     TYPE REF TO lcl_chapter
      RETURNING VALUE(rv_name) TYPE string.
    DATA mv_test TYPE abap_bool.
    DATA mv_over TYPE abap_bool.
    DATA mv_act  TYPE abap_bool.
*   mv_pack und mv_tr sind das Paket und der Auftrag des Objekts, das
*   gerade geschrieben wird - nicht die Eingabe vom Bild. Die steht in
*   mv_pack0 und mv_tr0. Vor jedem Objekt setzt set_pack( ) die beiden
*   um; so bleiben die zwanzig Stellen, die mv_pack lesen, unberuehrt.
    DATA mv_pack TYPE devclass.
    DATA mv_tr   TYPE trkorr.
    DATA mv_pack0 TYPE devclass.
    DATA mv_tr0   TYPE trkorr.
    DATA mv_keep  TYPE abap_bool.
    DATA mt_map   TYPE ty_packmaps.
*   Welche Regel schon einmal gegriffen hat. Eine Meldung je Regel, nicht
*   je Objekt - sonst steht das Protokoll voll mit derselben Zeile.
    DATA mt_said  TYPE STANDARD TABLE OF string WITH EMPTY KEY.
    DATA mt_log  TYPE ty_implog.

    METHODS set_pack IMPORTING io_chapter TYPE REF TO lcl_chapter.
    METHODS warn_no_order IMPORTING iv_pack TYPE devclass.

    METHODS collect
      IMPORTING io_chapter TYPE REF TO lcl_chapter
      CHANGING  ct_work    TYPE ty_impwork.
    METHODS log
      IMPORTING iv_kind   TYPE string
                iv_name   TYPE string
                iv_action TYPE string
                iv_text   TYPE string OPTIONAL.
    METHODS last_message RETURNING VALUE(rv_text) TYPE string.
    METHODS act_reason
      IMPORTING iv_kind        TYPE string
                iv_name        TYPE string
      RETURNING VALUE(rv_text) TYPE string.
    METHODS exists
      IMPORTING iv_kind        TYPE string
                iv_name        TYPE string
      RETURNING VALUE(rv_flag) TYPE abap_bool.
    METHODS tadir
      IMPORTING iv_object      TYPE trobjtype
                iv_name        TYPE sobj_name
      RETURNING VALUE(rv_ok)   TYPE abap_bool.
    METHODS put_doma IMPORTING io_chapter TYPE REF TO lcl_chapter
                               iv_name    TYPE string.
    METHODS put_dtel IMPORTING io_chapter TYPE REF TO lcl_chapter
                               iv_name    TYPE string.
    METHODS put_tabl IMPORTING io_chapter TYPE REF TO lcl_chapter
                               iv_name    TYPE string.
    METHODS put_prog IMPORTING io_chapter TYPE REF TO lcl_chapter
                               iv_name    TYPE string.
    METHODS put_dynp IMPORTING io_chapter TYPE REF TO lcl_chapter
                               iv_prog    TYPE progname.
    METHODS put_tran IMPORTING io_chapter TYPE REF TO lcl_chapter
                               iv_name    TYPE string.
    METHODS put_vcls IMPORTING io_chapter TYPE REF TO lcl_chapter
                               iv_name    TYPE string.
    METHODS put_maint IMPORTING io_chapter TYPE REF TO lcl_chapter
                                iv_name    TYPE string.
    METHODS put_cua  IMPORTING io_chapter TYPE REF TO lcl_chapter
                               iv_prog    TYPE progname.
    METHODS put_msag IMPORTING io_chapter TYPE REF TO lcl_chapter
                               iv_name    TYPE string.
    METHODS put_wbsrc IMPORTING io_chapter TYPE REF TO lcl_chapter
                                iv_kind    TYPE string
                                iv_name    TYPE string.
    METHODS put_srvb  IMPORTING io_chapter TYPE REF TO lcl_chapter
                                iv_name    TYPE string.
    METHODS put_wapa  IMPORTING io_chapter TYPE REF TO lcl_chapter
                                iv_name    TYPE string.
    METHODS put_segm  IMPORTING io_chapter TYPE REF TO lcl_chapter
                                iv_name    TYPE string.
    METHODS put_idoc  IMPORTING io_chapter TYPE REF TO lcl_chapter
                                iv_name    TYPE string.
*   Adobe-Form-Schnittstelle (SFPI) ueber die Form-Workbench anlegen.
    METHODS put_sfpi  IMPORTING io_chapter TYPE REF TO lcl_chapter
                                iv_name    TYPE string.
    METHODS sfp_exists
      IMPORTING iv_kind        TYPE string
                iv_name        TYPE string
      RETURNING VALUE(rv_flag) TYPE abap_bool.
    METHODS sfp_code_row
      IMPORTING io_chapter     TYPE REF TO lcl_chapter
                iv_tag         TYPE string
      RETURNING VALUE(rt_code) TYPE tfpcoding.
*   Adobe-Formular (SFPF) aus der SAP-eigenen Serialisierung wieder
*   anlegen - derselbe Weg, den die Kopierfunktion der Transaktion SFP
*   nimmt (CL_FP_HELPER).
    METHODS put_sfpf  IMPORTING io_chapter TYPE REF TO lcl_chapter
                                iv_name    TYPE string.
*   Checks after the run what actually stands in the system. An object
*   can be created and still be unusable - a structure whose data
*   element is missing activates with rc 8 - and an object written early
*   can be broken by one written later.
    METHODS verify IMPORTING it_work TYPE ty_impwork.
    METHODS verify_one
      IMPORTING is_work        TYPE ty_impwork_row
      RETURNING VALUE(rv_text) TYPE string.
    METHODS put_index IMPORTING io_chapter TYPE REF TO lcl_chapter
                                iv_name    TYPE string.
    METHODS put_view IMPORTING io_chapter TYPE REF TO lcl_chapter
                               iv_name    TYPE string.
    METHODS put_ddls IMPORTING io_chapter TYPE REF TO lcl_chapter
                               iv_name    TYPE string.
    METHODS put_clif IMPORTING io_chapter TYPE REF TO lcl_chapter
                               iv_kind    TYPE string
                               iv_name    TYPE string.
    METHODS put_fugr IMPORTING io_chapter TYPE REF TO lcl_chapter
                               iv_name    TYPE string.
    METHODS put_func IMPORTING io_chapter TYPE REF TO lcl_chapter
                               is_row     TYPE ty_defrow
                               iv_area    TYPE string.
    METHODS put_docu IMPORTING io_chapter TYPE REF TO lcl_chapter
                               iv_kind    TYPE string
                               iv_name    TYPE string.
*   Source of one row or of the whole definition as a line table.
    METHODS to_lines
      IMPORTING iv_source       TYPE string
      RETURNING VALUE(rt_lines) TYPE ty_code.
    METHODS activate
      IMPORTING iv_object TYPE trobjtype
                iv_name   TYPE string
      RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS prefix
      IMPORTING iv_text        TYPE string
                iv_pref        TYPE string
      RETURNING VALUE(rv_flag) TYPE abap_bool.
    METHODS func_body
      IMPORTING iv_source       TYPE string
      RETURNING VALUE(rt_lines) TYPE string_table.
ENDCLASS.

CLASS lcl_importer IMPLEMENTATION.

  METHOD constructor.
    mv_test  = iv_test.
    mv_over  = iv_over.
    mv_act   = iv_act.
    mv_pack  = iv_pack.
    mv_tr    = iv_tr.
    mv_pack0 = iv_pack.
    mv_tr0   = iv_tr.
    mv_keep  = iv_keep.
    mt_map   = it_map.
  ENDMETHOD.

  METHOD warn_no_order.

*   TR_TADIR_INTERFACE verlangt bei einem transportfaehigen Paket keinen
*   Auftrag: ohne KORRNUM legt es den Katalogeintrag an und meldet
*   sy-subrc 0. Auf S4H nachgemessen. Es kommt also kein Dialog - aber
*   auch kein Auftragseintrag. Die Objekte stehen dann im Paket und in
*   keinem Auftrag, und das faellt erst beim Transportieren auf.
    IF mv_tr IS NOT INITIAL.
      RETURN.
    ENDIF.

    DATA(lv_key) = |?{ iv_pack }|.
    READ TABLE mt_said TRANSPORTING NO FIELDS WITH KEY table_line = lv_key.
    IF sy-subrc = 0.
      RETURN.
    ENDIF.
    APPEND lv_key TO mt_said.

    log( iv_kind   = 'PACK'
         iv_name   = CONV string( iv_pack )
         iv_action = lcl_t=>ui( d = `ohne Auftrag` e = `without a request` )
         iv_text   = lcl_t=>ui(
           d = `Paket ist transportfaehig, aber kein Auftrag angegeben - die Objekte entstehen ausserhalb jedes Auftrags.`
           e = `package is transportable but no request was given - the objects are created outside any request.` ) ).

  ENDMETHOD.

  METHOD set_pack.

*   Das Zielpaket je Objekt. Reihenfolge:
*     1. eine Regel auf das Quellpaket
*     2. sonst das Quellpaket selbst, wenn "beibehalten" gesetzt ist
*     3. sonst das Zielpaket vom Bild
*
*   Das Quellpaket steht am Kapitel: der Export schreibt es in die
*   Objektreferenz. Fehlt es - ein Dokument aus einer aelteren Fassung -
*   greift Fall 3.
    DATA lv_new TYPE devclass.
    DATA lv_src TYPE devclass.

    mv_pack = mv_pack0.
    mv_tr   = mv_tr0.
    IF mv_pack NP '$*'.
      warn_no_order( mv_pack ).
    ENDIF.

    IF io_chapter IS NOT BOUND.
      RETURN.
    ENDIF.

*   Objekt-Umbenennung mit eigenem Zielpaket: die editierbare Liste
*   gewinnt vor den Paketregeln. Der Name im Dokument ist hier bereits
*   der neue.
    IF mt_ren IS NOT INITIAL.
      READ TABLE mt_ren INTO DATA(ls_rn)
        WITH KEY kind    = io_chapter->get_defkind( )
                 newname = obj_name( io_chapter ).
      IF sy-subrc = 0 AND ls_rn-newpack IS NOT INITIAL.
        mv_pack = ls_rn-newpack.
        IF mv_pack CP '$*'.
          CLEAR mv_tr.
        ELSE.
          mv_tr = mv_tr0.
          warn_no_order( mv_pack ).
        ENDIF.
        RETURN.
      ENDIF.
    ENDIF.

    lv_src = io_chapter->get_reference( )-tcode.
    IF lv_src IS INITIAL.
      RETURN.
    ENDIF.

    READ TABLE mt_map INTO DATA(ls_map) WITH KEY from = lv_src.
    IF sy-subrc = 0.
      lv_new = ls_map-to.
    ELSEIF mv_keep = abap_true.
      lv_new = lv_src.
    ELSE.
      RETURN.
    ENDIF.

    IF lv_new IS INITIAL OR lv_new = mv_pack0.
      RETURN.
    ENDIF.

*   Ein Paket, das es hier nicht gibt, wird nicht angelegt - das ist eine
*   Entscheidung, die dem Entwickler gehoert. Stattdessen bleibt es beim
*   Zielpaket vom Bild, und das Protokoll sagt warum.
    IF lv_new NP '$*'.
      SELECT COUNT(*) FROM tdevc WHERE devclass = @lv_new.
      DATA(lv_ex) = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).
      IF lv_ex <> abap_true.
        DATA(lv_key) = |!{ lv_new }|.
        READ TABLE mt_said TRANSPORTING NO FIELDS WITH KEY table_line = lv_key.
        IF sy-subrc <> 0.
          APPEND lv_key TO mt_said.
          log( iv_kind   = 'PACK'
               iv_name   = CONV string( lv_new )
               iv_action = lcl_t=>ui( d = `nicht verwendet` e = `not used` )
               iv_text   = |{ lcl_t=>ui( d = `Paket gibt es hier nicht, es bleibt bei`
                                         e = `package does not exist here, staying with` ) } | &&
                           |{ mv_pack0 }| ).
        ENDIF.
        RETURN.
      ENDIF.
    ENDIF.

    mv_pack = lv_new.

*   Ein lokales Paket kennt keinen Auftrag, ein transportfaehiges
*   braucht einen. Beides haengt am Paket dieses Objekts, nicht an der
*   Eingabe vom Bild.
    IF mv_pack CP '$*'.
      CLEAR mv_tr.
    ELSE.
      mv_tr = mv_tr0.
      warn_no_order( mv_pack ).
    ENDIF.

    DATA(lv_note) = |{ lv_src }>{ mv_pack }|.
    READ TABLE mt_said TRANSPORTING NO FIELDS WITH KEY table_line = lv_note.
    IF sy-subrc <> 0.
      APPEND lv_note TO mt_said.
      log( iv_kind   = 'PACK'
           iv_name   = CONV string( lv_src )
           iv_action = lcl_t=>ui( d = `Paket gesetzt` e = `package mapped` )
           iv_text   = |{ lv_src } -> { mv_pack }| ).
    ENDIF.

  ENDMETHOD.

  METHOD get_log.
    rt_log = mt_log.
  ENDMETHOD.

  METHOD act_reason.

*   Warum die Aktivierung nicht geklappt hat. DDIF_*_ACTIVATE gibt nur
*   einen Code heraus - rc 8 heisst "ging nicht" und sonst nichts. Wer
*   das liest, muss raten.
*
*   In aller Regel fehlt ein Baustein, auf dem das Objekt steht: die
*   Domaene unter dem Datenelement, das Datenelement unter dem Feld, die
*   Basistabelle unter dem View. Genau danach wird hier gesucht, und
*   zwar nach dem aktiven Stand - ein inaktiv angelegter Vorgaenger
*   traegt die Aktivierung nicht.
    DATA lv_obj TYPE ddobjname.
    DATA lt_mis TYPE STANDARD TABLE OF string WITH EMPTY KEY.

    lv_obj = iv_name.

    CASE iv_kind.

      WHEN 'DTEL'.
        SELECT SINGLE domname FROM dd04l
          WHERE rollname = @lv_obj AND as4local = 'L'
          INTO @DATA(lv_dom).
        IF sy-subrc <> 0.
          SELECT SINGLE domname FROM dd04l
            WHERE rollname = @lv_obj AND as4local = 'A'
            INTO @lv_dom.
        ENDIF.
        IF lv_dom IS NOT INITIAL.
          SELECT COUNT(*) FROM dd01l WHERE domname = @lv_dom AND as4local = 'A'.
          DATA(lv_dok) = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).
          IF lv_dok <> abap_true.
            APPEND |{ lcl_t=>ui( d = `Domaene` e = `domain` ) } { lv_dom }| TO lt_mis.
          ENDIF.
        ENDIF.

      WHEN 'TABL' OR 'VIEW'.
*       Die Datenelemente der Felder. Mehr als drei zu nennen hilft
*       niemandem - wer drei fehlende sieht, weiss Bescheid.
        SELECT DISTINCT rollname FROM dd03l
          WHERE tabname = @lv_obj AND rollname <> ''
          INTO TABLE @DATA(lt_rl).
        LOOP AT lt_rl INTO DATA(ls_rl).
          SELECT COUNT(*) FROM dd04l WHERE rollname = @ls_rl-rollname AND as4local = 'A'.
          DATA(lv_dtok) = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).
          IF lv_dtok <> abap_true.
            APPEND |{ lcl_t=>ui( d = `Datenelement` e = `data element` ) }| &&
                   | { ls_rl-rollname }| TO lt_mis.
          ENDIF.
          IF lines( lt_mis ) >= 3.
            EXIT.
          ENDIF.
        ENDLOOP.

    ENDCASE.

    IF lt_mis IS INITIAL.
      RETURN.
    ENDIF.

    LOOP AT lt_mis INTO DATA(lv_m).
      IF rv_text IS INITIAL.
        rv_text = |{ lcl_t=>ui( d = `fehlt oder inaktiv:` e = `missing or inactive:` ) } { lv_m }|.
      ELSE.
        rv_text = |{ rv_text }, { lv_m }|.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD last_message.

*   Die Meldung, die der gerufene Baustein vor seinem RAISE abgesetzt
*   hat. Sie muss unmittelbar nach dem Aufruf gelesen werden - jeder
*   weitere Aufruf ueberschreibt sy-msgid und sy-msgno.
*
*   Ohne sie steht im Protokoll nur eine Nummer. subrc 5 an
*   SEO_CLASS_CREATE_COMPLETE heisst NO_ACCESS, und das kann die
*   Berechtigung sein, eine Sperre oder das Korrektursystem - welches
*   davon, sagt erst die Meldung.
    IF sy-msgid IS INITIAL OR sy-msgno IS INITIAL.
      RETURN.
    ENDIF.

    MESSAGE ID sy-msgid TYPE 'S' NUMBER sy-msgno
            WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4
            INTO rv_text.

  ENDMETHOD.

  METHOD log.
    APPEND VALUE ty_implog_row( kind   = iv_kind
                                name   = iv_name
                                action = iv_action
                                text   = iv_text ) TO mt_log.
  ENDMETHOD.

  METHOD run.

    DATA lt_work TYPE ty_impwork.

    LOOP AT io_document->get_chapters( ) INTO DATA(lo_chapter).
      collect( EXPORTING io_chapter = lo_chapter CHANGING ct_work = lt_work ).
    ENDLOOP.

    IF lt_work IS INITIAL.
      log( iv_kind   = ''
           iv_name   = ''
           iv_action = lcl_t=>ui( d = `nichts zu tun`
                                  e = `nothing to do` )
           iv_text   = lcl_t=>ui( d = `Das Dokument enthaelt keine Definitionsdaten. Beim Export muss "Definitionsdaten fuer Reimport" angehakt sein.`
                                  e = `The document carries no definition data. The export needs "Definition data for reimport" switched on.` ) ).
      RETURN.
    ENDIF.

*   Domains before data elements before tables before programs.
    SORT lt_work BY seq name.

    LOOP AT lt_work INTO DATA(ls_work).
      set_pack( ls_work-chapter ).
      CASE ls_work-kind.
        WHEN 'DOMA'. put_doma( io_chapter = ls_work-chapter iv_name = ls_work-name ).
        WHEN 'DTEL'. put_dtel( io_chapter = ls_work-chapter iv_name = ls_work-name ).
        WHEN 'TABL'. put_tabl( io_chapter = ls_work-chapter iv_name = ls_work-name ).
        WHEN 'VIEW'. put_view( io_chapter = ls_work-chapter iv_name = ls_work-name ).
        WHEN 'DDLS'. put_ddls( io_chapter = ls_work-chapter iv_name = ls_work-name ).
        WHEN 'PROG'. put_prog( io_chapter = ls_work-chapter iv_name = ls_work-name ).
        WHEN 'CLAS' OR 'INTF'.
          put_clif( io_chapter = ls_work-chapter
                    iv_kind    = ls_work-kind
                    iv_name    = ls_work-name ).
        WHEN 'FUGR'. put_fugr( io_chapter = ls_work-chapter iv_name = ls_work-name ).
        WHEN 'MSAG'. put_msag( io_chapter = ls_work-chapter iv_name = ls_work-name ).
        WHEN 'BDEF' OR 'SRVD' OR 'DDLX'.
          put_wbsrc( io_chapter = ls_work-chapter
                     iv_kind    = ls_work-kind
                     iv_name    = ls_work-name ).
        WHEN 'SRVB'.
          put_srvb( io_chapter = ls_work-chapter iv_name = ls_work-name ).
        WHEN 'SEGM'.
          put_segm( io_chapter = ls_work-chapter iv_name = ls_work-name ).
        WHEN 'IDOC'.
          put_idoc( io_chapter = ls_work-chapter iv_name = ls_work-name ).
        WHEN 'WAPA'.
          put_wapa( io_chapter = ls_work-chapter iv_name = ls_work-name ).
        WHEN 'TRAN'.
          put_tran( io_chapter = ls_work-chapter iv_name = ls_work-name ).
        WHEN 'VCLS'.
          put_vcls( io_chapter = ls_work-chapter iv_name = ls_work-name ).
        WHEN 'SFPI'.
          put_sfpi( io_chapter = ls_work-chapter iv_name = ls_work-name ).
        WHEN 'SFPF'.
          put_sfpf( io_chapter = ls_work-chapter iv_name = ls_work-name ).
      ENDCASE.
    ENDLOOP.

*   Der Korrektursystem-Teil laeuft ueber die Verbuchung: der
*   Auftragseintrag und die Aufgabe darunter entstehen erst mit einem
*   COMMIT WORK. Ohne ihn meldet der Lauf, dass eine Aufgabe angelegt
*   wird, und im Transport Organizer steht keine.
*
*   AND WAIT, damit die Pruefung danach den fertigen Stand sieht und
*   nicht den halben.
    IF mv_test = abap_false.
      COMMIT WORK AND WAIT.
    ENDIF.

*   A test run wrote nothing, so there is nothing to check.
    IF mv_test = abap_false.
      verify( lt_work ).
    ENDIF.

  ENDMETHOD.

  METHOD verify.

    DATA lv_ok  TYPE i.
    DATA lv_bad TYPE i.

    LOOP AT it_work INTO DATA(ls_work).
      DATA(lv_text) = verify_one( ls_work ).
      IF lv_text IS INITIAL.
        lv_ok = lv_ok + 1.
      ELSE.
        lv_bad = lv_bad + 1.
        log( iv_kind   = ls_work-kind
             iv_name   = ls_work-name
             iv_action = lcl_t=>ui( d = `PRUEFUNG` e = `CHECK` )
             iv_text   = lv_text ).
      ENDIF.
    ENDLOOP.

    log( iv_kind   = ''
         iv_name   = ''
         iv_action = lcl_t=>ui( d = `Pruefung` e = `Check` )
         iv_text   = |{ lv_ok } { lcl_t=>ui( d = `in Ordnung` e = `fine` ) }, | &&
                     |{ lv_bad } { lcl_t=>ui( d = `mit Befund` e = `with findings` ) }| ).

  ENDMETHOD.

  METHOD verify_one.

    DATA lv_obj  TYPE ddobjname.
    DATA lv_act  TYPE abap_bool.
    DATA lv_prog TYPE progname.

    lv_obj = is_work-name.

    CASE is_work-kind.

      WHEN 'DOMA'.
        SELECT COUNT(*) FROM dd01l WHERE domname = @lv_obj AND as4local = 'A'.
        lv_act = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).
      WHEN 'DTEL'.
        SELECT COUNT(*) FROM dd04l WHERE rollname = @lv_obj AND as4local = 'A'.
        lv_act = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).
      WHEN 'TABL'.
        SELECT COUNT(*) FROM dd02l WHERE tabname = @lv_obj AND as4local = 'A'.
        lv_act = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).
      WHEN 'VIEW'.
        SELECT COUNT(*) FROM dd25l WHERE viewname = @lv_obj AND as4local = 'A'.
        lv_act = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).

      WHEN 'BDEF' OR 'SRVD' OR 'DDLX' OR 'SRVB'.
*       Aktiv heisst hier: der Operator laedt es. Ein Katalogeintrag
*       allein sagt bei diesen Arten nichts.
        lv_act = lcl_wb=>exists( iv_type = CONV trobjtype( is_work-kind )
                                 iv_name = is_work-name ).

      WHEN 'TRAN'.
        DATA lv_vtc TYPE tstc-tcode.
        lv_vtc = is_work-name.
        SELECT COUNT(*) FROM tstc WHERE tcode = @lv_vtc.
        lv_act = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).

      WHEN 'VCLS'.
*       Ein Cluster ohne Knoten ist kein Cluster. Der Kopfeintrag
*       allein sagt hier nichts.
        DATA lv_vvc TYPE vcldir-vclname.
        lv_vvc = is_work-name.
        SELECT COUNT(*) FROM vclstruc WHERE vclname = @lv_vvc.
        lv_act = boolc( sy-dbcnt > 0 ).

      WHEN 'WAPA'.
        cl_o2_api_application=>check_exist(
          EXPORTING p_application = CONV o2applname( is_work-name )
          IMPORTING p_exists      = lv_act ).

      WHEN 'SEGM'.
        DATA lv_vsg TYPE edisegment-segtyp.
        lv_vsg = is_work-name.
        SELECT COUNT(*) FROM edisegment WHERE segtyp = @lv_vsg.
        lv_act = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).

      WHEN 'IDOC'.
*       Ein Basistyp ohne Segmenthierarchie ist kein Basistyp. Gefragt
*       wird die API, nicht EDISYN: dort steht nur die freigegebene
*       Syntax, und ein frisch angelegter Typ ist nicht freigegeben.
        DATA lv_vid TYPE edi_iapi00-idoctyp.
        DATA ls_vat TYPE edi_iapi01.
        DATA lt_vsy TYPE STANDARD TABLE OF edi_iapi02 WITH EMPTY KEY.
        lv_vid = is_work-name.
        CALL FUNCTION 'IDOCTYPE_READ'
          EXPORTING  pi_idoctyp         = lv_vid
                     pi_check_authority = abap_true
          IMPORTING  pe_attributes      = ls_vat
          TABLES     pt_syntax          = lt_vsy
          EXCEPTIONS object_not_found   = 1
                     no_authority       = 2
                     db_error           = 3
                     OTHERS             = 4.
        lv_act = boolc( sy-subrc = 0 AND lt_vsy IS NOT INITIAL ).

      WHEN 'MSAG'.
*       The class alone is not enough - a class without its numbers
*       leaves the report showing the bare key just the same.
        DATA lv_arb TYPE t100a-arbgb.
        lv_arb = is_work-name.
        SELECT COUNT(*) FROM t100 WHERE arbgb = @lv_arb.
        lv_act = boolc( sy-dbcnt > 0 ).

      WHEN 'DDLS'.
        DATA lv_ddl TYPE ddldependency-ddlname.
        lv_ddl = is_work-name.
        SELECT COUNT(*) FROM ddldependency WHERE ddlname = @lv_ddl AND state = 'A'.
        lv_act = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).

      WHEN 'CLAS' OR 'INTF'.
        DATA lv_cls TYPE seoclassdf-clsname.
        lv_cls = is_work-name.
        SELECT COUNT(*) FROM seoclassdf WHERE clsname = @lv_cls AND version = '1'.
        lv_act = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).

      WHEN 'FUGR'.
*       A function group is active when nothing of it is left inactive.
        lv_act = abap_true.
        SELECT COUNT(*) FROM dwinactiv WHERE uname = @sy-uname.
        IF sy-subrc = 0.
          SELECT obj_name FROM dwinactiv WHERE uname = @sy-uname
            INTO TABLE @DATA(lt_in).
          LOOP AT lt_in INTO DATA(ls_in).
            IF prefix( iv_text = CONV string( ls_in-obj_name )
                       iv_pref = |SAPL{ is_work-name }| ) = abap_true
               OR prefix( iv_text = CONV string( ls_in-obj_name )
                          iv_pref = |L{ is_work-name }| ) = abap_true.
              CLEAR lv_act.
              EXIT.
            ENDIF.
          ENDLOOP.
        ENDIF.

      WHEN 'PROG'.
*       For a program the real check is the syntax check - it is the one
*       that notices when something the program uses is missing.
        DATA lt_code TYPE ty_code.
        DATA lv_msg  TYPE string.
        DATA lv_lin  TYPE i.
        DATA lv_wrd  TYPE string.

        lv_prog = is_work-name.
        READ REPORT lv_prog INTO lt_code.
        IF sy-subrc <> 0.
          rv_text = lcl_t=>ui( d = `nicht vorhanden` e = `does not exist` ).
          RETURN.
        ENDIF.
        SYNTAX-CHECK FOR lt_code PROGRAM lv_prog
                     MESSAGE lv_msg LINE lv_lin WORD lv_wrd.
        IF sy-subrc <> 0.
          rv_text = |{ lcl_t=>ui( d = `Syntaxfehler Zeile` e = `syntax error line` ) }| &&
                    | { lv_lin }: { lv_msg }|.
        ENDIF.
        RETURN.

      WHEN OTHERS.
        RETURN.

    ENDCASE.

    IF lv_act = abap_false.
      rv_text = lcl_t=>ui( d = `nicht aktiv` e = `not active` ).
    ENDIF.

  ENDMETHOD.

  METHOD collect.

    IF io_chapter->has_definition( ) = abap_true.
      DATA(lv_kind) = io_chapter->get_defkind( ).
      DATA lv_seq TYPE i.
      CASE lv_kind.
*       A message class stands on nothing and everything else may raise
*       one of its messages, so it goes first.
        WHEN 'MSAG'. lv_seq = 1.
        WHEN 'DOMA'. lv_seq = 1.
        WHEN 'DTEL'. lv_seq = 2.
        WHEN 'TABL'. lv_seq = 3.
*       Ein Segment steht auf Datenelementen, ein Basistyp auf seinen
*       Segmenten. Mit Tabelle und View haben beide nichts zu tun.
        WHEN 'SEGM'. lv_seq = 3.
        WHEN 'IDOC'. lv_seq = 4.
*       A view stands on tables, a CDS source on both.
        WHEN 'VIEW'. lv_seq = 4.
        WHEN 'DDLS'. lv_seq = 5.
*       A metadata extension extends a CDS view, a behaviour definition
*       defines behaviour for one - both need it to be there first.
        WHEN 'DDLX'. lv_seq = 6.
        WHEN 'BDEF'. lv_seq = 7.
        WHEN 'PROG'. lv_seq = 8.
*       Interfaces before classes - a class implements them. Function
*       groups last; their modules tend to use everything above.
        WHEN 'INTF'. lv_seq = 9.
        WHEN 'CLAS'. lv_seq = 10.
        WHEN 'FUGR'. lv_seq = 11.
*       A service definition exposes CDS views, a binding stands on the
*       definition. Both at the end, they are the outermost layer.
        WHEN 'SRVD'. lv_seq = 12.
        WHEN 'SRVB'. lv_seq = 13.
*       Die UI5-Anwendung ganz zuletzt: sie ruft die Services auf,
*       die vorher entstehen muessen.
        WHEN 'WAPA'. lv_seq = 14.
*       Die Transaktion steht auf Programm oder Funktionsgruppe, der
*       View-Cluster auf den Views seiner Knoten. Beide ganz zuletzt.
        WHEN 'VCLS'. lv_seq = 15.
        WHEN 'TRAN'. lv_seq = 16.
*       Adobe-Form-Schnittstelle: steht auf ihren DDIC-Typen, das
*       Formular wiederum auf ihr. Beide ganz zuletzt.
        WHEN 'SFPI'. lv_seq = 17.
*       Das Formular steht auf seiner Schnittstelle - die muss vorher
*       da und aktiv sein.
        WHEN 'SFPF'. lv_seq = 18.
        WHEN OTHERS. lv_seq = 99.
      ENDCASE.

*     The name comes from the definition, never from the chapter title -
*     the title carries the short text as well and is translated.
      DATA(lv_name) = obj_name( io_chapter ).

      IF lv_name IS NOT INITIAL AND lv_seq < 99.
        APPEND VALUE ty_impwork_row( seq     = lv_seq
                                     kind    = lv_kind
                                     name    = lv_name
                                     chapter = io_chapter ) TO ct_work.
      ENDIF.
    ENDIF.

    LOOP AT io_chapter->get_children( ) INTO DATA(lo_child).
      collect( EXPORTING io_chapter = lo_child CHANGING ct_work = ct_work ).
    ENDLOOP.

  ENDMETHOD.

  METHOD obj_name.
*   Der Objektname je Objektart aus dem Kopf der Definitionsdaten - nie
*   aus dem (uebersetzten) Kapiteltitel. Von collect und set_pack genutzt.
    DATA(lv_kind) = io_chapter->get_defkind( ).
    DATA(lt_head) = io_chapter->get_defhead( ).
    CASE lv_kind.
      WHEN 'DOMA'. rv_name = lcl_attr=>value( it_attrs = lt_head iv_name = 'DOMNAME' ).
      WHEN 'DTEL'. rv_name = lcl_attr=>value( it_attrs = lt_head iv_name = 'ROLLNAME' ).
      WHEN 'TABL'. rv_name = lcl_attr=>value( it_attrs = lt_head iv_name = 'TABNAME' ).
      WHEN 'PROG'. rv_name = lcl_attr=>value( it_attrs = lt_head iv_name = 'NAME' ).
      WHEN 'VIEW'. rv_name = lcl_attr=>value( it_attrs = lt_head iv_name = 'VIEWNAME' ).
      WHEN 'DDLS'. rv_name = lcl_attr=>value( it_attrs = lt_head iv_name = 'DDLNAME' ).
      WHEN 'CLAS' OR 'INTF'. rv_name = lcl_attr=>value( it_attrs = lt_head iv_name = 'CLSNAME' ).
      WHEN 'FUGR'. rv_name = lcl_attr=>value( it_attrs = lt_head iv_name = 'AREA' ).
      WHEN 'MSAG'. rv_name = lcl_attr=>value( it_attrs = lt_head iv_name = 'ARBGB' ).
      WHEN 'SEGM'. rv_name = lcl_attr=>value( it_attrs = lt_head iv_name = 'SEGTYP' ).
      WHEN 'IDOC'. rv_name = lcl_attr=>value( it_attrs = lt_head iv_name = 'IDOCTYP' ).
      WHEN 'WAPA'. rv_name = lcl_attr=>value( it_attrs = lt_head iv_name = 'APPLNAME' ).
      WHEN 'BDEF' OR 'SRVD' OR 'DDLX' OR 'SRVB'.
        rv_name = lcl_attr=>value( it_attrs = lt_head iv_name = 'NAME' ).
      WHEN 'TRAN'. rv_name = lcl_attr=>value( it_attrs = lt_head iv_name = 'TCODE' ).
      WHEN 'VCLS'. rv_name = lcl_attr=>value( it_attrs = lt_head iv_name = 'VCLNAME' ).
      WHEN 'SFPI' OR 'SFPF'. rv_name = lcl_attr=>value( it_attrs = lt_head iv_name = 'NAME' ).
    ENDCASE.
  ENDMETHOD.

  METHOD plan.
    LOOP AT io_document->get_chapters( ) INTO DATA(lo_ch).
      collect( EXPORTING io_chapter = lo_ch CHANGING ct_work = rt_work ).
    ENDLOOP.
  ENDMETHOD.

  METHOD set_renames.
    mt_ren = it_ren.
  ENDMETHOD.

  METHOD exists.

    DATA lv_obj TYPE ddobjname.
    DATA lv_prg TYPE progname.

    lv_obj = iv_name.
    CASE iv_kind.
      WHEN 'DOMA'.
        SELECT COUNT(*) FROM dd01l WHERE domname = @lv_obj AND as4local = 'A'.
        rv_flag = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).
      WHEN 'DTEL'.
        SELECT COUNT(*) FROM dd04l WHERE rollname = @lv_obj AND as4local = 'A'.
        rv_flag = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).
      WHEN 'TABL'.
        SELECT COUNT(*) FROM dd02l WHERE tabname = @lv_obj AND as4local = 'A'.
        rv_flag = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).
      WHEN 'PROG'.
        lv_prg = iv_name.
        SELECT COUNT(*) FROM trdir WHERE name = @lv_prg.
        rv_flag = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).
      WHEN 'VIEW'.
        SELECT COUNT(*) FROM dd25l WHERE viewname = @lv_obj AND as4local = 'A'.
        rv_flag = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).
      WHEN 'DDLS'.
        DATA lv_ddl TYPE ddlname.
        lv_ddl = iv_name.
        SELECT COUNT(*) FROM ddddlsrc WHERE ddlname = @lv_ddl AND as4local = 'A'.
        rv_flag = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).
      WHEN 'CLAS' OR 'INTF'.
        DATA lv_cls TYPE seoclsname.
        lv_cls = iv_name.
        SELECT COUNT(*) FROM seoclass WHERE clsname = @lv_cls.
        rv_flag = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).
      WHEN 'FUGR'.
        DATA lv_are TYPE rs38l-area.
        lv_are = iv_name.
        SELECT COUNT(*) FROM tlibg WHERE area = @lv_are.
        rv_flag = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).
      WHEN 'MSAG'.
        DATA lv_arb TYPE t100a-arbgb.
        lv_arb = iv_name.
        SELECT COUNT(*) FROM t100a WHERE arbgb = @lv_arb.
        rv_flag = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).

      WHEN 'SEGM'.
        DATA lv_sgt TYPE edisegment-segtyp.
        lv_sgt = iv_name.
        SELECT COUNT(*) FROM edisegment WHERE segtyp = @lv_sgt.
        rv_flag = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).

      WHEN 'IDOC'.
        DATA lv_idt TYPE edbas-idoctyp.
        lv_idt = iv_name.
        SELECT COUNT(*) FROM edbas WHERE idoctyp = @lv_idt.
        rv_flag = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).

      WHEN 'TRAN'.
        DATA lv_tcd TYPE tstc-tcode.
        lv_tcd = iv_name.
        SELECT COUNT(*) FROM tstc WHERE tcode = @lv_tcd.
        rv_flag = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).

      WHEN 'VCLS'.
        DATA lv_vcn TYPE vcldir-vclname.
        lv_vcn = iv_name.
        SELECT COUNT(*) FROM vcldir WHERE vclname = @lv_vcn.
        rv_flag = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).

      WHEN 'WAPA'.
*       Nicht der Katalog, sondern die API - auf S4H stehen
*       WAPA-Eintraege ohne Anwendung dahinter.
        cl_o2_api_application=>check_exist(
          EXPORTING p_application = CONV o2applname( iv_name )
          IMPORTING p_exists      = rv_flag ).

      WHEN 'BDEF' OR 'SRVD' OR 'DDLX' OR 'SRVB'.
*       Der Katalog taugt hier nicht als Nachweis - auf S4H stehen
*       reihenweise Eintraege ohne Objekt dahinter. Gefragt wird den
*       Operator, der das Objekt tatsaechlich laden muesste.
        rv_flag = lcl_wb=>exists( iv_type = CONV trobjtype( iv_kind )
                                  iv_name = iv_name ).
    ENDCASE.

  ENDMETHOD.

  METHOD to_lines.

    DATA lt_str TYPE STANDARD TABLE OF string WITH EMPTY KEY.

    SPLIT iv_source AT cl_abap_char_utilities=>newline INTO TABLE lt_str.
    LOOP AT lt_str INTO DATA(lv_line).
      APPEND CONV char255( lv_line ) TO rt_lines.
    ENDLOOP.

  ENDMETHOD.

  METHOD activate.

    DATA lt_all  TYPE STANDARD TABLE OF dwinactiv WITH EMPTY KEY.
    DATA lt_obj  TYPE STANDARD TABLE OF dwinactiv WITH EMPTY KEY.
    DATA lv_keep TYPE abap_bool.
    DATA lv_main TYPE progname.

*   Only the parts that belong to the object just written. The list of
*   inactive objects is per user and regularly holds unfinished work of
*   the person running the import - activating all of it would push
*   someone else's half-finished class into the active version.
    SELECT * FROM dwinactiv WHERE uname = @sy-uname INTO TABLE @lt_all.
    IF lt_all IS INITIAL.
      rv_ok = abap_true.
      RETURN.
    ENDIF.

    IF iv_object = 'FUGR'.
      lv_main = |SAPL{ iv_name }|.
      SELECT funcname FROM tfdir WHERE pname = @lv_main
        INTO TABLE @DATA(lt_fn).
    ENDIF.

    LOOP AT lt_all INTO DATA(ls_in).
      CLEAR lv_keep.
      CASE iv_object.
        WHEN 'CLAS' OR 'INTF'.
*         The parts of a class carry the class name padded with equals
*         signs, so a prefix test catches them all.
          lv_keep = prefix( iv_text = CONV string( ls_in-obj_name )
                            iv_pref = iv_name ).
        WHEN 'PROG'.
          IF ls_in-obj_name = iv_name.
            lv_keep = abap_true.
          ENDIF.
        WHEN 'FUGR'.
          IF prefix( iv_text = CONV string( ls_in-obj_name )
                     iv_pref = |SAPL{ iv_name }| ) = abap_true
             OR prefix( iv_text = CONV string( ls_in-obj_name )
                        iv_pref = |L{ iv_name }| ) = abap_true.
            lv_keep = abap_true.
          ELSEIF ls_in-object = 'FUNC'.
            READ TABLE lt_fn TRANSPORTING NO FIELDS
                 WITH KEY funcname = ls_in-obj_name.
            IF sy-subrc = 0.
              lv_keep = abap_true.
            ENDIF.
          ENDIF.
      ENDCASE.
      IF lv_keep = abap_true.
        APPEND ls_in TO lt_obj.
      ENDIF.
    ENDLOOP.

    IF lt_obj IS INITIAL.
*     Nothing inactive - the write went straight into the active version.
      rv_ok = abap_true.
      RETURN.
    ENDIF.

    CALL FUNCTION 'RS_WORKING_OBJECTS_ACTIVATE'
      EXPORTING  activate_ddic_objects  = abap_false
                 with_popup             = abap_false
                 suppress_corr_insert   = abap_true
      TABLES     objects                = lt_obj
      EXCEPTIONS excecution_error       = 1
                 cancelled              = 2
                 insert_into_corr_error = 3
                 OTHERS                 = 4.
    IF sy-subrc = 0.
      rv_ok = abap_true.
    ENDIF.

  ENDMETHOD.

  METHOD func_body.

*   RPY_FUNCTIONMODULE_READ hands out the whole include: the FUNCTION
*   statement, the interface as a comment block, the body and
*   ENDFUNCTION. RPY_FUNCTIONMODULE_INSERT writes those three itself and
*   wants the body alone - given the whole thing, the module ends up with
*   two ENDFUNCTION statements.
    DATA lt_all TYPE STANDARD TABLE OF string WITH EMPTY KEY.
    DATA lv_up  TYPE string.
    DATA lv_beg TYPE i.
    DATA lv_end TYPE i.

    SPLIT iv_source AT cl_abap_char_utilities=>newline INTO TABLE lt_all.
    lv_end = lines( lt_all ).

    LOOP AT lt_all INTO DATA(lv_line).
      lv_up = to_upper( lv_line ).
      SHIFT lv_up LEFT DELETING LEADING space.
      IF lv_beg = 0 AND lv_up CP 'FUNCTION *'.
        lv_beg = sy-tabix.
      ELSEIF lv_up CP 'ENDFUNCTION*'.
        lv_end = sy-tabix - 1.
      ENDIF.
    ENDLOOP.

*   Everything up to and including FUNCTION, plus the comment block that
*   documents the interface right after it.
    IF lv_beg > 0.
      LOOP AT lt_all INTO lv_line FROM lv_beg + 1.
        lv_up = lv_line.
        SHIFT lv_up LEFT DELETING LEADING space.
        IF lv_up(2) = '*"'.
          lv_beg = sy-tabix.
        ELSE.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDIF.

    LOOP AT lt_all INTO lv_line FROM lv_beg + 1 TO lv_end.
      APPEND lv_line TO rt_lines.
    ENDLOOP.

  ENDMETHOD.

  METHOD prefix.
    IF strlen( iv_text ) >= strlen( iv_pref )
       AND substring( val = iv_text len = strlen( iv_pref ) ) = iv_pref.
      rv_flag = abap_true.
    ENDIF.
  ENDMETHOD.

  METHOD tadir.

*   The parameters of TR_TADIR_INTERFACE are typed against the fields of
*   TADIR. A merely convertible field is not enough there - SY-SYSID is
*   eight characters, TADIR-SRCSYSTEM ten, and the call ends in
*   CALL_FUNCTION_CONFLICT_TYPE. Hence one local per field, typed after
*   the table.
    DATA lv_corr TYPE tadir-korrnum.
    DATA lv_srcs TYPE tadir-srcsystem.
    DATA lv_auth TYPE tadir-author.
    DATA lv_lang TYPE tadir-masterlang.

*   $TMP and the other local packages carry no transport, and asking the
*   correction system for one there ends in a dialog nobody sees.
    IF mv_pack NP '$*'.
      lv_corr = mv_tr.
    ENDIF.
    lv_srcs = sy-sysid.
    lv_auth = sy-uname.
    lv_lang = sy-langu.

    CALL FUNCTION 'TR_TADIR_INTERFACE'
      EXPORTING  wi_test_modus                  = abap_false
                 wi_tadir_pgmid                 = 'R3TR'
                 wi_tadir_object                = iv_object
                 wi_tadir_obj_name              = iv_name
                 wi_tadir_devclass              = mv_pack
                 wi_tadir_masterlang            = lv_lang
                 wi_tadir_author                = lv_auth
                 wi_tadir_srcsystem             = lv_srcs
                 wi_tadir_korrnum               = lv_corr
      EXCEPTIONS tadir_entry_not_existing       = 1
                 tadir_entry_ill_type           = 2
                 no_systemname                  = 3
                 no_systemtype                  = 4
                 original_system_conflict       = 5
                 object_reserved_for_devclass   = 6
                 object_exists_global           = 7
                 object_exists_local            = 8
                 object_is_distributed          = 9
                 obj_specification_not_unique   = 10
                 no_authorization_to_delete     = 11
                 devclass_not_existing          = 12
                 simultanious_set_remove_repair = 13
                 order_missing                  = 14
                 no_modification_of_head_syst   = 15
                 pgmid_object_not_allowed       = 16
                 masterlanguage_not_specified   = 17
                 devclass_not_specified         = 18
                 specify_owner_unique           = 19
                 loc_priv_objs_no_repair        = 20
                 gtadir_not_reached             = 21
                 object_locked_for_order        = 22
                 change_of_class_not_allowed    = 23
                 no_change_from_sap_to_tmp      = 24
                 OTHERS                         = 25.
    IF sy-subrc = 0.
      rv_ok = abap_true.
    ENDIF.

  ENDMETHOD.

  METHOD put_doma.

    DATA ls_dd01v TYPE dd01v.
    DATA lt_dd07v TYPE STANDARD TABLE OF dd07v WITH EMPTY KEY.
    DATA ls_dd07v TYPE dd07v.
    DATA lv_obj   TYPE ddobjname.
    DATA lv_rc    TYPE sy-subrc.

    DATA(lv_ex) = exists( iv_kind = 'DOMA' iv_name = iv_name ).
    IF lv_ex = abap_true AND mv_over = abap_false.
      log( iv_kind = 'DOMA' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `uebersprungen` e = `skipped` )
           iv_text   = lcl_t=>ui( d = `existiert bereits` e = `already exists` ) ).
      RETURN.
    ENDIF.

    lcl_attr=>to_struct( EXPORTING it_attrs = io_chapter->get_defhead( )
                         CHANGING  cs_data  = ls_dd01v ).
    LOOP AT io_chapter->get_defrows( ) INTO DATA(ls_row) WHERE tag = 'DD07V'.
      CLEAR ls_dd07v.
      lcl_attr=>to_struct( EXPORTING it_attrs = ls_row-attrs
                           CHANGING  cs_data  = ls_dd07v ).
      APPEND ls_dd07v TO lt_dd07v.
    ENDLOOP.

    IF mv_test = abap_true.
      log( iv_kind = 'DOMA' iv_name = iv_name
           iv_action = COND #( WHEN lv_ex = abap_true
                               THEN lcl_t=>ui( d = `wuerde geaendert` e = `would change` )
                               ELSE lcl_t=>ui( d = `wuerde angelegt` e = `would create` ) )
           iv_text   = |{ ls_dd01v-datatype } { ls_dd01v-leng }, | &&
                       |{ lines( lt_dd07v ) } | &&
                       |{ lcl_t=>ui( d = `Festwerte` e = `fixed values` ) }| ).
      RETURN.
    ENDIF.

    lv_obj = iv_name.
    CALL FUNCTION 'DDIF_DOMA_PUT'
      EXPORTING  name              = lv_obj
                 dd01v_wa          = ls_dd01v
      TABLES     dd07v_tab         = lt_dd07v
      EXCEPTIONS doma_not_found    = 1
                 name_inconsistent = 2
                 doma_inconsistent = 3
                 put_refused       = 4
                 OTHERS            = 5.
    IF sy-subrc <> 0.
      DATA(lv_rc1) = sy-subrc.
      DATA(lv_msg1) = last_message( ).
      log( iv_kind = 'DOMA' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `Fehler` e = `error` )
           iv_text   = |DDIF_DOMA_PUT subrc { lv_rc1 } { lv_msg1 }| ).
      RETURN.
    ENDIF.

    tadir( iv_object = 'DOMA' iv_name = CONV sobj_name( iv_name ) ).

    IF mv_act = abap_true.
      CALL FUNCTION 'DDIF_DOMA_ACTIVATE'
        EXPORTING  name        = lv_obj
                   auth_chk    = abap_true
        IMPORTING  rc          = lv_rc
        EXCEPTIONS not_found   = 1
                   put_failure = 2
                   OTHERS      = 3.
      IF sy-subrc <> 0 OR lv_rc > 4.
        log( iv_kind = 'DOMA' iv_name = iv_name
             iv_action = lcl_t=>ui( d = `angelegt, inaktiv` e = `created, inactive` )
             iv_text   = |DDIF_DOMA_ACTIVATE rc { lv_rc }| ).
        RETURN.
      ENDIF.
    ENDIF.

    log( iv_kind = 'DOMA' iv_name = iv_name
         iv_action = COND #( WHEN lv_ex = abap_true
                             THEN lcl_t=>ui( d = `geaendert` e = `changed` )
                             ELSE lcl_t=>ui( d = `angelegt` e = `created` ) ) ).
    put_docu( io_chapter = io_chapter iv_kind = 'DOMA' iv_name = iv_name ).

  ENDMETHOD.

  METHOD put_dtel.

    DATA ls_dd04v TYPE dd04v.
    DATA lv_obj   TYPE ddobjname.
    DATA lv_rc    TYPE sy-subrc.

    DATA(lv_ex) = exists( iv_kind = 'DTEL' iv_name = iv_name ).
    IF lv_ex = abap_true AND mv_over = abap_false.
      log( iv_kind = 'DTEL' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `uebersprungen` e = `skipped` )
           iv_text   = lcl_t=>ui( d = `existiert bereits` e = `already exists` ) ).
      RETURN.
    ENDIF.

    lcl_attr=>to_struct( EXPORTING it_attrs = io_chapter->get_defhead( )
                         CHANGING  cs_data  = ls_dd04v ).

    IF mv_test = abap_true.
      log( iv_kind = 'DTEL' iv_name = iv_name
           iv_action = COND #( WHEN lv_ex = abap_true
                               THEN lcl_t=>ui( d = `wuerde geaendert` e = `would change` )
                               ELSE lcl_t=>ui( d = `wuerde angelegt` e = `would create` ) )
           iv_text   = COND #( WHEN ls_dd04v-domname IS NOT INITIAL
                               THEN |{ lcl_t=>ui( d = `Domaene` e = `domain` ) } { ls_dd04v-domname }|
                               ELSE |{ ls_dd04v-datatype } { ls_dd04v-leng }| ) ).
      RETURN.
    ENDIF.

    lv_obj = iv_name.
    CALL FUNCTION 'DDIF_DTEL_PUT'
      EXPORTING  name              = lv_obj
                 dd04v_wa          = ls_dd04v
      EXCEPTIONS dtel_not_found    = 1
                 name_inconsistent = 2
                 dtel_inconsistent = 3
                 put_refused       = 4
                 OTHERS            = 5.
    IF sy-subrc <> 0.
      DATA(lv_rc2) = sy-subrc.
      DATA(lv_msg2) = last_message( ).
      log( iv_kind = 'DTEL' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `Fehler` e = `error` )
           iv_text   = |DDIF_DTEL_PUT subrc { lv_rc2 } { lv_msg2 }| ).
      RETURN.
    ENDIF.

    tadir( iv_object = 'DTEL' iv_name = CONV sobj_name( iv_name ) ).

    IF mv_act = abap_true.
      CALL FUNCTION 'DDIF_DTEL_ACTIVATE'
        EXPORTING  name        = lv_obj
                   auth_chk    = abap_true
        IMPORTING  rc          = lv_rc
        EXCEPTIONS not_found   = 1
                   put_failure = 2
                   OTHERS      = 3.
      IF sy-subrc <> 0 OR lv_rc > 4.
        DATA(lv_why_dtel) = act_reason( iv_kind = 'DTEL' iv_name = iv_name ).
        log( iv_kind = 'DTEL' iv_name = iv_name
             iv_action = lcl_t=>ui( d = `angelegt, inaktiv` e = `created, inactive` )
             iv_text   = |DDIF_DTEL_ACTIVATE rc { lv_rc } { lv_why_dtel }| ).
        RETURN.
      ENDIF.
    ENDIF.

    log( iv_kind = 'DTEL' iv_name = iv_name
         iv_action = COND #( WHEN lv_ex = abap_true
                             THEN lcl_t=>ui( d = `geaendert` e = `changed` )
                             ELSE lcl_t=>ui( d = `angelegt` e = `created` ) ) ).
    put_docu( io_chapter = io_chapter iv_kind = 'DTEL' iv_name = iv_name ).

  ENDMETHOD.

  METHOD put_tabl.

    DATA ls_dd02v TYPE dd02v.
    DATA ls_dd09v TYPE dd09v.
    DATA lt_dd03p TYPE STANDARD TABLE OF dd03p WITH EMPTY KEY.
    DATA lt_dd05m TYPE STANDARD TABLE OF dd05m WITH EMPTY KEY.
    DATA lt_dd08v TYPE STANDARD TABLE OF dd08v WITH EMPTY KEY.
    DATA lt_dd35v TYPE STANDARD TABLE OF dd35v WITH EMPTY KEY.
    DATA lt_dd36m TYPE STANDARD TABLE OF dd36m WITH EMPTY KEY.
    DATA ls_dd03p TYPE dd03p.
    DATA ls_dd05m TYPE dd05m.
    DATA ls_dd08v TYPE dd08v.
    DATA ls_dd35v TYPE dd35v.
    DATA ls_dd36m TYPE dd36m.
    DATA lv_obj   TYPE ddobjname.
    DATA lv_rc    TYPE sy-subrc.

    DATA(lv_ex) = exists( iv_kind = 'TABL' iv_name = iv_name ).
    IF lv_ex = abap_true AND mv_over = abap_false.
      log( iv_kind = 'TABL' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `uebersprungen` e = `skipped` )
           iv_text   = lcl_t=>ui( d = `existiert bereits` e = `already exists` ) ).
      RETURN.
    ENDIF.

    lcl_attr=>to_struct( EXPORTING it_attrs = io_chapter->get_defhead( )
                         CHANGING  cs_data  = ls_dd02v ).

    LOOP AT io_chapter->get_defrows( ) INTO DATA(ls_row).
      CASE ls_row-tag.
        WHEN 'DD09V'.
          lcl_attr=>to_struct( EXPORTING it_attrs = ls_row-attrs
                               CHANGING  cs_data  = ls_dd09v ).
        WHEN 'DD03P'.
          CLEAR ls_dd03p.
          lcl_attr=>to_struct( EXPORTING it_attrs = ls_row-attrs
                               CHANGING  cs_data  = ls_dd03p ).
          APPEND ls_dd03p TO lt_dd03p.
        WHEN 'DD05M'.
          CLEAR ls_dd05m.
          lcl_attr=>to_struct( EXPORTING it_attrs = ls_row-attrs
                               CHANGING  cs_data  = ls_dd05m ).
          APPEND ls_dd05m TO lt_dd05m.
        WHEN 'DD08V'.
          CLEAR ls_dd08v.
          lcl_attr=>to_struct( EXPORTING it_attrs = ls_row-attrs
                               CHANGING  cs_data  = ls_dd08v ).
          APPEND ls_dd08v TO lt_dd08v.
        WHEN 'DD35V'.
          CLEAR ls_dd35v.
          lcl_attr=>to_struct( EXPORTING it_attrs = ls_row-attrs
                               CHANGING  cs_data  = ls_dd35v ).
          APPEND ls_dd35v TO lt_dd35v.
        WHEN 'DD36M'.
          CLEAR ls_dd36m.
          lcl_attr=>to_struct( EXPORTING it_attrs = ls_row-attrs
                               CHANGING  cs_data  = ls_dd36m ).
          APPEND ls_dd36m TO lt_dd36m.
      ENDCASE.
    ENDLOOP.

    DATA(lv_nidx) = REDUCE i( INIT n = 0 FOR r IN io_chapter->get_defrows( )
                              NEXT n = COND #( WHEN r-tag = 'DD12V' THEN n + 1 ELSE n ) ).

    IF mv_test = abap_true.
      log( iv_kind = 'TABL' iv_name = iv_name
           iv_action = COND #( WHEN lv_ex = abap_true
                               THEN lcl_t=>ui( d = `wuerde geaendert` e = `would change` )
                               ELSE lcl_t=>ui( d = `wuerde angelegt` e = `would create` ) )
           iv_text   = |{ ls_dd02v-tabclass }, { lines( lt_dd03p ) } | &&
                       |{ lcl_t=>ui( d = `Felder` e = `fields` ) }| &&
                       COND string( WHEN lv_nidx > 0
                                    THEN |, { lv_nidx } { lcl_t=>ui( d = `Indizes` e = `indexes` ) }|
                                    ELSE `` ) ).
      put_maint( io_chapter = io_chapter iv_name = iv_name ).
      RETURN.
    ENDIF.

    lv_obj = iv_name.
    CALL FUNCTION 'DDIF_TABL_PUT'
      EXPORTING  name              = lv_obj
                 dd02v_wa          = ls_dd02v
                 dd09l_wa          = ls_dd09v
      TABLES     dd03p_tab         = lt_dd03p
                 dd05m_tab         = lt_dd05m
                 dd08v_tab         = lt_dd08v
                 dd35v_tab         = lt_dd35v
                 dd36m_tab         = lt_dd36m
      EXCEPTIONS tabl_not_found    = 1
                 name_inconsistent = 2
                 tabl_inconsistent = 3
                 put_refused       = 4
                 OTHERS            = 5.
    IF sy-subrc <> 0.
      DATA(lv_rc3) = sy-subrc.
      DATA(lv_msg3) = last_message( ).
      log( iv_kind = 'TABL' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `Fehler` e = `error` )
           iv_text   = |DDIF_TABL_PUT subrc { lv_rc3 } { lv_msg3 }| ).
      RETURN.
    ENDIF.

    tadir( iv_object = 'TABL' iv_name = CONV sobj_name( iv_name ) ).

    IF mv_act = abap_true.
      CALL FUNCTION 'DDIF_TABL_ACTIVATE'
        EXPORTING  name        = lv_obj
                   auth_chk    = abap_true
        IMPORTING  rc          = lv_rc
        EXCEPTIONS not_found   = 1
                   put_failure = 2
                   OTHERS      = 3.
      IF sy-subrc <> 0 OR lv_rc > 4.
        DATA(lv_why_tabl) = act_reason( iv_kind = 'TABL' iv_name = iv_name ).
        log( iv_kind = 'TABL' iv_name = iv_name
             iv_action = lcl_t=>ui( d = `angelegt, inaktiv` e = `created, inactive` )
             iv_text   = |DDIF_TABL_ACTIVATE rc { lv_rc } { lv_why_tabl }| ).
        RETURN.
      ENDIF.
    ENDIF.

    log( iv_kind = 'TABL' iv_name = iv_name
         iv_action = COND #( WHEN lv_ex = abap_true
                             THEN lcl_t=>ui( d = `geaendert` e = `changed` )
                             ELSE lcl_t=>ui( d = `angelegt` e = `created` ) ) ).
    put_docu( io_chapter = io_chapter iv_kind = 'TABL' iv_name = iv_name ).

*   Only now, with the table active: an index on a table that is not
*   there yet cannot be activated.
*
*   The activation grades its result: 0 is clean, 4 means activated with
*   a warning, 8 and above means it did not work. Only from 8 upwards
*   does the object stay inactive - treating 4 as a failure would stop
*   the run on a table that is perfectly usable.
    IF lv_nidx > 0.
      put_index( io_chapter = io_chapter iv_name = iv_name ).
    ENDIF.

    put_maint( io_chapter = io_chapter iv_name = iv_name ).

  ENDMETHOD.

  METHOD put_index.

    DATA ls_dd12v TYPE dd12v.
    DATA ls_dd17v TYPE dd17v.
    DATA lt_dd17v TYPE STANDARD TABLE OF dd17v WITH EMPTY KEY.
    DATA lv_obj   TYPE ddobjname.
    DATA lv_id    TYPE ddobjectid.
    DATA lv_rc    TYPE sy-subrc.

    lv_obj = iv_name.

    LOOP AT io_chapter->get_defrows( ) INTO DATA(ls_row) WHERE tag = 'DD12V'.
      CLEAR: ls_dd12v, lt_dd17v.
      lcl_attr=>to_struct( EXPORTING it_attrs = ls_row-attrs
                           CHANGING  cs_data  = ls_dd12v ).
      IF ls_dd12v-indexname IS INITIAL.
        CONTINUE.
      ENDIF.
      lv_id = ls_dd12v-indexname.
*     The index name ties header and fields together; both carry it.
      ls_dd12v-sqltab = lv_obj.
*     DBINDEX holds the name on the database and is built from the table
*     name. Carried over unchanged it would still name the table of the
*     source system; the activation puts the right one in.
      CLEAR: ls_dd12v-dbindex, ls_dd12v-as4user,
             ls_dd12v-as4date, ls_dd12v-as4time.

      LOOP AT io_chapter->get_defrows( ) INTO DATA(ls_f) WHERE tag = 'DD17V'.
        IF lcl_attr=>value( it_attrs = ls_f-attrs iv_name = 'INDEXNAME' ) <> lv_id.
          CONTINUE.
        ENDIF.
        CLEAR ls_dd17v.
        lcl_attr=>to_struct( EXPORTING it_attrs = ls_f-attrs
                             CHANGING  cs_data  = ls_dd17v ).
        ls_dd17v-sqltab = lv_obj.
        APPEND ls_dd17v TO lt_dd17v.
      ENDLOOP.

      CALL FUNCTION 'DDIF_INDX_PUT'
        EXPORTING  name              = lv_obj
                   id                = lv_id
                   dd12v_wa          = ls_dd12v
        TABLES     dd17v_tab         = lt_dd17v
        EXCEPTIONS indx_not_found    = 1
                   name_inconsistent = 2
                   indx_inconsistent = 3
                   put_refused       = 4
                   OTHERS            = 5.
      IF sy-subrc <> 0.
        DATA(lv_rc4) = sy-subrc.
        DATA(lv_msg4) = last_message( ).
        log( iv_kind = 'INDX' iv_name = |{ iv_name }-{ lv_id }|
             iv_action = lcl_t=>ui( d = `Fehler` e = `error` )
             iv_text   = |DDIF_INDX_PUT subrc { lv_rc4 } { lv_msg4 }| ).
        CONTINUE.
      ENDIF.

      IF mv_act = abap_true.
        CALL FUNCTION 'DDIF_INDX_ACTIVATE'
          EXPORTING  name        = lv_obj
                     id          = lv_id
                     auth_chk    = abap_true
          IMPORTING  rc          = lv_rc
          EXCEPTIONS not_found   = 1
                     put_failure = 2
                     OTHERS      = 3.
        IF sy-subrc <> 0 OR lv_rc > 4.
          log( iv_kind = 'INDX' iv_name = |{ iv_name }-{ lv_id }|
               iv_action = lcl_t=>ui( d = `angelegt, inaktiv` e = `created, inactive` )
               iv_text   = |DDIF_INDX_ACTIVATE rc { lv_rc }| ).
          CONTINUE.
        ENDIF.
      ENDIF.

      log( iv_kind = 'INDX' iv_name = |{ iv_name }-{ lv_id }|
           iv_action = lcl_t=>ui( d = `angelegt` e = `created` )
           iv_text   = |{ lines( lt_dd17v ) } { lcl_t=>ui( d = `Felder` e = `fields` ) }| ).
    ENDLOOP.

  ENDMETHOD.

  METHOD put_prog.

    DATA ls_trdir TYPE trdir.
    DATA lt_src   TYPE STANDARD TABLE OF string WITH EMPTY KEY.
    DATA lt_code  TYPE STANDARD TABLE OF char255 WITH EMPTY KEY.
    DATA lt_tpool TYPE STANDARD TABLE OF textpool WITH EMPTY KEY.
    DATA ls_tp    TYPE textpool.
    DATA lv_prog  TYPE progname.

    DATA(lv_ex) = exists( iv_kind = 'PROG' iv_name = iv_name ).
    IF lv_ex = abap_true AND mv_over = abap_false.
      log( iv_kind = 'PROG' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `uebersprungen` e = `skipped` )
           iv_text   = lcl_t=>ui( d = `existiert bereits` e = `already exists` ) ).
      RETURN.
    ENDIF.

    DATA(lv_source) = io_chapter->get_defsource( ).
    IF lv_source IS INITIAL.
      log( iv_kind = 'PROG' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `nicht moeglich` e = `not possible` )
           iv_text   = lcl_t=>ui( d = `kein Quelltext im Dokument`
                                  e = `no source in the document` ) ).
      RETURN.
    ENDIF.
    SPLIT lv_source AT cl_abap_char_utilities=>newline INTO TABLE lt_src.
    LOOP AT lt_src INTO DATA(lv_line).
      APPEND CONV char255( lv_line ) TO lt_code.
    ENDLOOP.

    lcl_attr=>to_struct( EXPORTING it_attrs = io_chapter->get_defhead( )
                         CHANGING  cs_data  = ls_trdir ).
*   Who wrote it in the source system is of no interest here, and a
*   foreign name in the directory entry only confuses the target system.
    CLEAR: ls_trdir-cnam, ls_trdir-cdat, ls_trdir-unam, ls_trdir-udat,
           ls_trdir-vern, ls_trdir-levl, ls_trdir-rmand, ls_trdir-sdate,
           ls_trdir-stime, ls_trdir-idate, ls_trdir-itime.
    ls_trdir-name = iv_name.

    TYPES: BEGIN OF ty_tpl,
             langu TYPE sy-langu,
             tp    TYPE textpool,
           END OF ty_tpl.
    DATA lt_tpl TYPE STANDARD TABLE OF ty_tpl WITH EMPTY KEY.

    LOOP AT io_chapter->get_defrows( ) INTO DATA(ls_row) WHERE tag = 'TPOOL'.
      CLEAR ls_tp.
      lcl_attr=>to_struct( EXPORTING it_attrs = ls_row-attrs
                           CHANGING  cs_data  = ls_tp ).
      APPEND ls_tp TO lt_tpool.
*     Die Sprache, in der die Zeile gelesen wurde. Aeltere Dokumente
*     tragen sie nicht; dann bleibt es beim bisherigen Verhalten.
      DATA(lv_tpls) = lcl_attr=>value( it_attrs = ls_row-attrs iv_name = '_SPRSL' ).
      APPEND VALUE ty_tpl( langu = COND #( WHEN lv_tpls IS NOT INITIAL
                                           THEN lv_tpls ELSE sy-langu )
                           tp    = ls_tp ) TO lt_tpl.
    ENDLOOP.

    IF mv_test = abap_true.
      DATA(lv_ncua) = REDUCE i( INIT n = 0
                                FOR ls_c IN io_chapter->get_defrows( )
                                WHERE ( tag = 'CUA_STA' )
                                NEXT n = n + 1 ).
      log( iv_kind = 'PROG' iv_name = iv_name
           iv_action = COND #( WHEN lv_ex = abap_true
                               THEN lcl_t=>ui( d = `wuerde geaendert` e = `would change` )
                               ELSE lcl_t=>ui( d = `wuerde angelegt` e = `would create` ) )
           iv_text   = |{ lcl_t=>ui( d = `Art` e = `type` ) } { ls_trdir-subc }, | &&
                       |{ lines( lt_code ) } { lcl_t=>ui( d = `Zeilen` e = `lines` ) }, | &&
                       |{ lines( lt_tpool ) } { lcl_t=>ui( d = `Textelemente` e = `text elements` ) }, | &&
                       |{ lv_ncua } { lcl_t=>ui( d = `GUI-Status` e = `GUI statuses` ) }| ).
      RETURN.
    ENDIF.

    lv_prog = iv_name.
    INSERT REPORT lv_prog FROM lt_code DIRECTORY ENTRY ls_trdir.
    IF sy-subrc <> 0.
      DATA(lv_rc5) = sy-subrc.
      DATA(lv_msg5) = last_message( ).
      log( iv_kind = 'PROG' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `Fehler` e = `error` )
           iv_text   = |INSERT REPORT subrc { lv_rc5 } { lv_msg5 }| ).
      RETURN.
    ENDIF.

*   Je Sprache ein INSERT TEXTPOOL. Bisher ging alles in die
*   Anmeldesprache des Importierenden: englische Selektionstexte landeten
*   als deutsche, und in der eigentlichen Sprache stand nichts.
    DATA lt_tpone TYPE STANDARD TABLE OF textpool WITH EMPTY KEY.
    DATA lv_tpcur TYPE sy-langu.
    DATA lv_tplog TYPE string.
    SORT lt_tpl BY langu.
    LOOP AT lt_tpl INTO DATA(ls_tpl).
      IF ls_tpl-langu <> lv_tpcur AND lt_tpone IS NOT INITIAL.
        INSERT TEXTPOOL lv_prog FROM lt_tpone LANGUAGE lv_tpcur STATE 'A'.
        lv_tplog = |{ lv_tplog } { lv_tpcur }:{ lines( lt_tpone ) }|.
        CLEAR lt_tpone.
      ENDIF.
      lv_tpcur = ls_tpl-langu.
      APPEND ls_tpl-tp TO lt_tpone.
    ENDLOOP.
    IF lt_tpone IS NOT INITIAL.
      INSERT TEXTPOOL lv_prog FROM lt_tpone LANGUAGE lv_tpcur STATE 'A'.
      lv_tplog = |{ lv_tplog } { lv_tpcur }:{ lines( lt_tpone ) }|.
    ENDIF.

    tadir( iv_object = 'PROG' iv_name = CONV sobj_name( iv_name ) ).

    log( iv_kind = 'PROG' iv_name = iv_name
         iv_action = COND #( WHEN lv_ex = abap_true
                             THEN lcl_t=>ui( d = `geaendert` e = `changed` )
                             ELSE lcl_t=>ui( d = `angelegt` e = `created` ) )
         iv_text   = |{ lines( lt_code ) } { lcl_t=>ui( d = `Zeilen` e = `lines` ) }| ).

    IF lv_tplog IS NOT INITIAL.
      log( iv_kind = 'TEXT' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `Textelemente gesetzt` e = `text elements written` )
           iv_text   = condense( lv_tplog ) ).
    ENDIF.

    put_cua( io_chapter = io_chapter iv_prog = lv_prog ).
    put_docu( io_chapter = io_chapter iv_kind = 'PROG' iv_name = iv_name ).

  ENDMETHOD.

  METHOD put_wapa.

*   Die Anwendung geht ueber die UI5-Repository-API hinein, nicht ueber
*   die Seiten-API. Die legt zwar Seiten an, aber niemand findet sie
*   danach: Pfadzuordnung, MIME-Ordner, ICF-Knoten und Katalogeintrag
*   entstehen erst hier. CREATE_REPOSITORY und PUT_FILE arbeiten ohne
*   Dialog, wenn IV_DIALOG_MODE leer bleibt.
    DATA lo_ui5   TYPE REF TO object.
    DATA lv_appl  TYPE o2applname.
    DATA lv_corr  TYPE trkorr.
    DATA lv_dev   TYPE devclass.

    DATA(lv_ex) = exists( iv_kind = 'WAPA' iv_name = iv_name ).
    IF lv_ex = abap_true AND mv_over = abap_false.
      log( iv_kind = 'WAPA' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `uebersprungen` e = `skipped` )
           iv_text   = lcl_t=>ui( d = `existiert bereits` e = `already exists` ) ).
      RETURN.
    ENDIF.

    DATA(lt_rows) = io_chapter->get_defrows( ).
    DELETE lt_rows WHERE tag <> 'WAPA_FILE' AND tag <> 'WAPA_DIR'.
    IF lt_rows IS INITIAL.
      log( iv_kind = 'WAPA' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `nicht moeglich` e = `not possible` )
           iv_text   = lcl_t=>ui( d = `keine Dateien im Dokument`
                                  e = `no files in the document` ) ).
      RETURN.
    ENDIF.

    IF mv_test = abap_true.
      DATA lv_bytes TYPE i.
      DATA lv_files TYPE i.
      LOOP AT lt_rows INTO DATA(ls_cnt) WHERE tag = 'WAPA_FILE'.
        lv_files = lv_files + 1.
        lv_bytes = lv_bytes + lcl_attr=>value( it_attrs = ls_cnt-attrs
                                               iv_name  = 'SIZE' ).
      ENDLOOP.
      log( iv_kind = 'WAPA' iv_name = iv_name
           iv_action = COND #( WHEN lv_ex = abap_true
                               THEN lcl_t=>ui( d = `wuerde geaendert` e = `would change` )
                               ELSE lcl_t=>ui( d = `wuerde angelegt` e = `would create` ) )
           iv_text   = |{ lv_files } { lcl_t=>ui( d = `Dateien` e = `files` ) }, | &&
                       |{ lv_bytes } { lcl_t=>ui( d = `Bytes` e = `bytes` ) }| ).
      RETURN.
    ENDIF.

    lv_appl = iv_name.
    lv_dev  = mv_pack.
    IF mv_pack NP '$*'.
      lv_corr = mv_tr.
    ENDIF.

    DATA(lv_text) = lcl_attr=>value( it_attrs = io_chapter->get_defhead( )
                                     iv_name  = 'TEXT' ).

    IF lv_ex = abap_false.
      TRY.
          DATA(lv_unew) = CONV string( lv_appl ).
          CALL METHOD ('/UI5/CL_UI5_REP_DT')=>('/UI5/IF_UI5_REP_DT~CREATE_REPOSITORY')
            EXPORTING iv_name              = lv_unew
                      iv_description       = lv_text
                      iv_transport_request = lv_corr
                      iv_devclass          = lv_dev
                      iv_dialog_mode       = space
            RECEIVING ro_instance          = lo_ui5.
        CATCH cx_root INTO DATA(lx_new).
          log( iv_kind = 'WAPA' iv_name = iv_name
               iv_action = lcl_t=>ui( d = `Fehler` e = `error` )
               iv_text   = lx_new->get_text( ) ).
          RETURN.
      ENDTRY.
    ELSE.
      TRY.
          DATA(lv_uget) = CONV string( lv_appl ).
          CALL METHOD ('/UI5/CL_UI5_REP_DT')=>('/UI5/IF_UI5_REP_DT~GET_API')
            EXPORTING iv_name        = lv_uget
                      iv_dialog_mode = space
            RECEIVING ro_instance    = lo_ui5.
        CATCH cx_root INTO DATA(lx_get).
          log( iv_kind = 'WAPA' iv_name = iv_name
               iv_action = lcl_t=>ui( d = `Fehler` e = `error` )
               iv_text   = lx_get->get_text( ) ).
          RETURN.
      ENDTRY.
    ENDIF.

    DATA lv_ok   TYPE i.
    DATA lv_bad  TYPE i.
    DATA lv_sum  TYPE i.

*   Die Sperre haelt fuer den ganzen Lauf. Ohne sie fasst jede
*   Einzelschreibung die Zuordnungsdatei neu an.
    TRY.
        CALL METHOD lo_ui5->('/UI5/IF_UI5_REP_DT~LOCK').
      CATCH cx_root.
    ENDTRY.

*   Ordner vor Dateien - der Export liefert sie in dieser Reihenfolge,
*   aber verlassen wird sich darauf nicht.
    SORT lt_rows BY tag DESCENDING.

    LOOP AT lt_rows INTO DATA(ls_row).
      DATA(lv_path) = lcl_attr=>value( it_attrs = ls_row-attrs iv_name = 'PATH' ).
      IF lv_path IS INITIAL.
        CONTINUE.
      ENDIF.

      IF ls_row-tag = 'WAPA_DIR'.
        TRY.
            CALL METHOD lo_ui5->('/UI5/IF_UI5_REP_DT~CREATE_FOLDER')
              EXPORTING iv_path              = lv_path
                        iv_transport_request = lv_corr.
          CATCH cx_root.
*           Ein vorhandener Ordner ist kein Fehler.
        ENDTRY.
        CONTINUE.
      ENDIF.

      DATA lv_cont TYPE xstring.
      CLEAR lv_cont.
      TRY.
          lv_cont = cl_http_utility=>decode_x_base64( encoded = ls_row-src ).
        CATCH cx_root.
          lv_bad = lv_bad + 1.
          CONTINUE.
      ENDTRY.

      TRY.
          DATA(lv_umime) = lcl_attr=>value( it_attrs = ls_row-attrs
                                            iv_name  = 'MIMETYPE' ).
          CALL METHOD lo_ui5->('/UI5/IF_UI5_REP_DT~PUT_FILE')
            EXPORTING iv_path              = lv_path
                      iv_transport_request = lv_corr
                      iv_file_content      = lv_cont
                      iv_mime_type         = lv_umime.
          lv_ok  = lv_ok + 1.
          lv_sum = lv_sum + xstrlen( lv_cont ).
        CATCH cx_root.
          lv_bad = lv_bad + 1.
      ENDTRY.
    ENDLOOP.

    TRY.
        CALL METHOD lo_ui5->('/UI5/IF_UI5_REP_DT~UPDATE_FINISHED').
      CATCH cx_root.
    ENDTRY.
    TRY.
        CALL METHOD lo_ui5->('/UI5/IF_UI5_REP_DT~UNLOCK').
      CATCH cx_root.
    ENDTRY.

*   Den Katalogeintrag schreibt die API mit, wenn ein Paket mitkommt.
*   Sicherheitshalber nachziehen - eine Anwendung ohne Eintrag ist
*   nicht auslieferbar, und ein zweiter Aufruf schadet nicht.
    tadir( iv_object = 'WAPA' iv_name = CONV sobj_name( iv_name ) ).

    log( iv_kind = 'WAPA' iv_name = iv_name
         iv_action = COND #( WHEN lv_ex = abap_true
                             THEN lcl_t=>ui( d = `geaendert` e = `changed` )
                             ELSE lcl_t=>ui( d = `angelegt` e = `created` ) )
         iv_text   = |{ lv_ok } { lcl_t=>ui( d = `Dateien` e = `files` ) }, | &&
                     |{ lv_sum } { lcl_t=>ui( d = `Bytes` e = `bytes` ) }| &&
                     COND #( WHEN lv_bad > 0
                             THEN |, { lv_bad } { lcl_t=>ui( d = `nicht angelegt`
                                                             e = `not created` ) }|
                             ELSE `` ) ).

  ENDMETHOD.

  METHOD put_segm.

*   SEGMENT_CREATE legt Segmenttyp, Segmentdefinition und die
*   gleichnamige DDIC-Struktur in einem Zug an. Deshalb darf ein Segment
*   nicht als Tabelle importiert werden: der Weg ueber DDIF_TABL_PUT
*   erzeugte die Struktur ohne das Segment darum herum.
    DATA ls_head TYPE edisegmhd.
    DATA ls_def  TYPE edisegmdef.
    DATA lt_stru TYPE STANDARD TABLE OF edisegstru WITH EMPTY KEY.
    DATA lv_dev  TYPE tadir-devclass.
    DATA lv_ord  TYPE e070-trkorr.
    DATA lv_task TYPE e070-trkorr.

    DATA(lv_ex) = exists( iv_kind = 'SEGM' iv_name = iv_name ).
    IF lv_ex = abap_true AND mv_over = abap_false.
      log( iv_kind = 'SEGM' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `uebersprungen` e = `skipped` )
           iv_text   = lcl_t=>ui( d = `existiert bereits` e = `already exists` ) ).
      RETURN.
    ENDIF.

    lcl_attr=>to_struct( EXPORTING it_attrs = io_chapter->get_defhead( )
                         CHANGING  cs_data  = ls_head ).
    ls_head-segtyp = iv_name.
    CLEAR: ls_head-credate, ls_head-cretime, ls_head-ldate, ls_head-ltime.

    LOOP AT io_chapter->get_defrows( ) INTO DATA(ls_row) WHERE tag = 'SEGSTRU'.
      DATA ls_stru TYPE edisegstru.
      CLEAR ls_stru.
      lcl_attr=>to_struct( EXPORTING it_attrs = ls_row-attrs
                           CHANGING  cs_data  = ls_stru ).
      ls_stru-segtyp = iv_name.
      APPEND ls_stru TO lt_stru.
    ENDLOOP.

    IF lt_stru IS INITIAL.
      log( iv_kind = 'SEGM' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `nicht moeglich` e = `not possible` )
           iv_text   = lcl_t=>ui( d = `keine Felder im Dokument`
                                  e = `no fields in the document` ) ).
      RETURN.
    ENDIF.

    IF mv_test = abap_true.
      log( iv_kind = 'SEGM' iv_name = iv_name
           iv_action = COND #( WHEN lv_ex = abap_true
                               THEN lcl_t=>ui( d = `wuerde geaendert` e = `would change` )
                               ELSE lcl_t=>ui( d = `wuerde angelegt` e = `would create` ) )
           iv_text   = |{ lines( lt_stru ) } { lcl_t=>ui( d = `Felder` e = `fields` ) }| ).
      RETURN.
    ENDIF.

    IF lv_ex = abap_true.
*     Ein bestehendes Segment wird nicht angefasst. SEGMENT_MODIFY
*     haengt eine neue Segmentdefinition an, und das ist eine
*     Versionsentscheidung, die dem Entwickler gehoert.
      log( iv_kind = 'SEGM' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `uebersprungen` e = `skipped` )
           iv_text   = lcl_t=>ui( d = `vorhanden - neue Definition waere eine neue Version`
                                  e = `exists - a new definition would be a new version` ) ).
      RETURN.
    ENDIF.

    lv_dev = mv_pack.
    IF mv_pack NP '$*'.
      lv_ord = mv_tr.
    ENDIF.

*   DEVCLASS und ORDER sind CHANGING, nicht EXPORTING - der Baustein
*   gibt beide auch wieder heraus. Als EXPORTING uebergeben endete der
*   Aufruf in CALL_FUNCTION_PARM_UNKNOWN, und ORDER stand nur als
*   Variable herum, ohne je anzukommen: ein transportfaehiges Paket
*   haette den Auftrag nie gesehen.
    CALL FUNCTION 'SEGMENT_CREATE'
      EXPORTING  segmenteditor       = space
      IMPORTING  segmentdefinition   = ls_def
                 task                = lv_task
      TABLES     segmentstructure    = lt_stru
      CHANGING   segmentheader       = ls_head
                 devclass            = lv_dev
                 order               = lv_ord
      EXCEPTIONS lock_error          = 1
                 creation_failed     = 2
                 no_authority        = 3
                 transport_error     = 4
                 namespace_violation = 5
                 OTHERS              = 6.
    IF sy-subrc <> 0.
      DATA(lv_rc6) = sy-subrc.
      DATA(lv_msg6) = last_message( ).
      log( iv_kind = 'SEGM' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `Fehler` e = `error` )
           iv_text   = |SEGMENT_CREATE subrc { lv_rc6 } { lv_msg6 }| ).
      RETURN.
    ENDIF.

    log( iv_kind = 'SEGM' iv_name = iv_name
         iv_action = lcl_t=>ui( d = `angelegt` e = `created` )
         iv_text   = |{ lines( lt_stru ) } { lcl_t=>ui( d = `Felder` e = `fields` ) }| ).

  ENDMETHOD.

  METHOD put_idoc.

    DATA ls_attr TYPE edi_iapi05.
    DATA ls_out  TYPE edi_iapi01.
    DATA lt_syn  TYPE STANDARD TABLE OF edi_iapi02 WITH EMPTY KEY.
    DATA lv_idoc TYPE edi_iapi00-idoctyp.
    DATA lv_dev  TYPE edi_iapi00-devclass.
    DATA lv_ord  TYPE edi_iapi00-trkorr.

    DATA(lv_ex) = exists( iv_kind = 'IDOC' iv_name = iv_name ).
    IF lv_ex = abap_true AND mv_over = abap_false.
      log( iv_kind = 'IDOC' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `uebersprungen` e = `skipped` )
           iv_text   = lcl_t=>ui( d = `existiert bereits` e = `already exists` ) ).
      RETURN.
    ENDIF.

    lcl_attr=>to_struct( EXPORTING it_attrs = io_chapter->get_defhead( )
                         CHANGING  cs_data  = ls_attr ).
    ls_attr-idoctyp = iv_name.

    LOOP AT io_chapter->get_defrows( ) INTO DATA(ls_row) WHERE tag = 'SYNTAX'.
      DATA ls_syn TYPE edi_iapi02.
      CLEAR ls_syn.
      lcl_attr=>to_struct( EXPORTING it_attrs = ls_row-attrs
                           CHANGING  cs_data  = ls_syn ).
      APPEND ls_syn TO lt_syn.
    ENDLOOP.

    IF lt_syn IS INITIAL.
      log( iv_kind = 'IDOC' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `nicht moeglich` e = `not possible` )
           iv_text   = lcl_t=>ui( d = `keine Segmenthierarchie im Dokument`
                                  e = `no segment hierarchy in the document` ) ).
      RETURN.
    ENDIF.

    IF mv_test = abap_true.
      log( iv_kind = 'IDOC' iv_name = iv_name
           iv_action = COND #( WHEN lv_ex = abap_true
                               THEN lcl_t=>ui( d = `wuerde geaendert` e = `would change` )
                               ELSE lcl_t=>ui( d = `wuerde angelegt` e = `would create` ) )
           iv_text   = |{ lines( lt_syn ) } { lcl_t=>ui( d = `Segmente` e = `segments` ) }| ).
      RETURN.
    ENDIF.

    lv_idoc = iv_name.
    lv_dev  = mv_pack.
    IF mv_pack NP '$*'.
      lv_ord = mv_tr.
    ENDIF.

    IF lv_ex = abap_true.
      CALL FUNCTION 'IDOCTYPE_UPDATE'
        EXPORTING  pi_idoctyp          = lv_idoc
                   pi_attributes       = ls_attr
        IMPORTING  pe_attributes       = ls_out
        TABLES     pt_syntax           = lt_syn
        CHANGING   pc_order            = lv_ord
        EXCEPTIONS object_not_found    = 1
                   no_authority        = 2
                   db_error            = 3
                   object_exists       = 4
                   syntax_error        = 5
                   segment_error       = 6
                   transport_error     = 7
                   OTHERS              = 8.
    ELSE.
      CALL FUNCTION 'IDOCTYPE_CREATE'
        EXPORTING  pi_idoctyp          = lv_idoc
                   pi_attributes       = ls_attr
                   pi_devclass         = lv_dev
        IMPORTING  pe_attributes       = ls_out
        TABLES     pt_syntax           = lt_syn
        CHANGING   pc_order            = lv_ord
        EXCEPTIONS object_not_found    = 1
                   no_authority        = 2
                   db_error            = 3
                   object_exists       = 4
                   action_not_possible = 5
                   syntax_error        = 6
                   segment_error       = 7
                   transport_error     = 8
                   OTHERS              = 9.
    ENDIF.
    IF sy-subrc <> 0.
      DATA(lv_rc7) = sy-subrc.
      DATA(lv_msg7) = last_message( ).
      log( iv_kind = 'IDOC' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `Fehler` e = `error` )
           iv_text   = |{ COND #( WHEN lv_ex = abap_true
                                  THEN `IDOCTYPE_UPDATE` ELSE `IDOCTYPE_CREATE` ) } | &&
                       |subrc { lv_rc7 } { lv_msg7 }| ).
      RETURN.
    ENDIF.

    log( iv_kind = 'IDOC' iv_name = iv_name
         iv_action = COND #( WHEN lv_ex = abap_true
                             THEN lcl_t=>ui( d = `geaendert` e = `changed` )
                             ELSE lcl_t=>ui( d = `angelegt` e = `created` ) )
         iv_text   = |{ lines( lt_syn ) } { lcl_t=>ui( d = `Segmente` e = `segments` ) }| ).

  ENDMETHOD.

  METHOD put_srvb.

*   Das Gegenstueck zu def_srvb. Aus dem Kopf und den beiden Zeilenarten
*   entsteht die verschachtelte Struktur wieder: Services aus SRVB_SRV,
*   ihre Versionen aus SRVB_VER, zugeordnet ueber den Servicenamen.
*   Die Typen gehoeren CL_SRVB_OBJECT_DATA und entstehen zur Laufzeit.
    FIELD-SYMBOLS <ls_content> TYPE any.
    FIELD-SYMBOLS <lt_srv>     TYPE ANY TABLE.
    FIELD-SYMBOLS <ls_srv>     TYPE any.
    FIELD-SYMBOLS <lt_ver>     TYPE ANY TABLE.
    FIELD-SYMBOLS <ls_ver>     TYPE any.
    DATA lo_data TYPE REF TO object.
    DATA lo_op   TYPE REF TO object.
    DATA lv_corr TYPE trkorr.
    DATA lv_nsrv TYPE i.

    DATA(lv_ex) = exists( iv_kind = 'SRVB' iv_name = iv_name ).
    IF lv_ex = abap_true AND mv_over = abap_false.
      log( iv_kind = 'SRVB' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `uebersprungen` e = `skipped` )
           iv_text   = lcl_t=>ui( d = `existiert bereits` e = `already exists` ) ).
      RETURN.
    ENDIF.

    DATA(lr_content) = lcl_wb=>srvb_data( `TY_CONTENT` ).
    IF lr_content IS NOT BOUND.
      log( iv_kind = 'SRVB' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `nicht moeglich` e = `not possible` )
           iv_text   = lcl_t=>ui( d = `Service-Bindings gibt es in diesem System nicht`
                                  e = `service bindings do not exist in this system` ) ).
      RETURN.
    ENDIF.
    ASSIGN lr_content->* TO <ls_content>.

    DATA(lt_head)  = io_chapter->get_defhead( ).
    DATA(lv_btype) = lcl_attr=>value( it_attrs = lt_head iv_name = 'BIND_TYPE' ).
    DATA(lv_bcat)  = lcl_attr=>value( it_attrs = lt_head iv_name = 'BIND_TYPE_CATEGORY' ).
    DATA(lv_bver)  = lcl_attr=>value( it_attrs = lt_head iv_name = 'BIND_TYPE_VERSION' ).
    IF lv_btype IS INITIAL.
      log( iv_kind = 'SRVB' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `nicht moeglich` e = `not possible` )
           iv_text   = lcl_t=>ui( d = `keine Bindungsart im Dokument`
                                  e = `no binding type in the document` ) ).
      RETURN.
    ENDIF.
    lcl_wb=>set_comp( EXPORTING iv_path = `BIND_TYPE` iv_value = lv_btype
                      CHANGING  cs_data = <ls_content> ).
    lcl_wb=>set_comp( EXPORTING iv_path = `BIND_TYPE_CATEGORY` iv_value = lv_bcat
                      CHANGING  cs_data = <ls_content> ).
    lcl_wb=>set_comp( EXPORTING iv_path = `BIND_TYPE_VERSION` iv_value = lv_bver
                      CHANGING  cs_data = <ls_content> ).
*   Die Referenz auf die Bindungsart-Implementierung traegt den
*   Bindingnamen. Im Quellsystem stand hier derselbe Wert.
    lcl_wb=>set_comp( EXPORTING iv_path = `BIND_TYPE_IMPL-NAME` iv_value = iv_name
                      CHANGING  cs_data = <ls_content> ).

    ASSIGN COMPONENT 'SERVICES' OF STRUCTURE <ls_content> TO <lt_srv>.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    DATA(lt_rows) = io_chapter->get_defrows( ).
    LOOP AT lt_rows INTO DATA(ls_row) WHERE tag = 'SRVB_SRV'.
      DATA(lv_sname) = lcl_attr=>value( it_attrs = ls_row-attrs
                                        iv_name  = 'SERVICE_NAME' ).
      INSERT INITIAL LINE INTO TABLE <lt_srv> ASSIGNING <ls_srv>.
      lcl_wb=>set_comp( EXPORTING iv_path = `SERVICE_NAME` iv_value = lv_sname
                        CHANGING  cs_data = <ls_srv> ).
      lv_nsrv = lv_nsrv + 1.
      ASSIGN COMPONENT 'SERVICE_CONTENT' OF STRUCTURE <ls_srv> TO <lt_ver>.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      LOOP AT lt_rows INTO DATA(ls_vrow) WHERE tag = 'SRVB_VER'.
        IF lcl_attr=>value( it_attrs = ls_vrow-attrs iv_name = 'SERVICE_NAME' )
           <> lv_sname.
          CONTINUE.
        ENDIF.
        DATA(lv_vver) = lcl_attr=>value( it_attrs = ls_vrow-attrs iv_name = 'SERVICE_VERSION' ).
        DATA(lv_vrel) = lcl_attr=>value( it_attrs = ls_vrow-attrs iv_name = 'RELEASE_STATE' ).
        DATA(lv_vsrd) = lcl_attr=>value( it_attrs = ls_vrow-attrs iv_name = 'SRVD_NAME' ).
        INSERT INITIAL LINE INTO TABLE <lt_ver> ASSIGNING <ls_ver>.
        lcl_wb=>set_comp( EXPORTING iv_path = `SERVICE_VERSION` iv_value = lv_vver
                          CHANGING  cs_data = <ls_ver> ).
        lcl_wb=>set_comp( EXPORTING iv_path = `RELEASE_STATE` iv_value = lv_vrel
                          CHANGING  cs_data = <ls_ver> ).
        lcl_wb=>set_comp( EXPORTING iv_path = `SRVD_REF-NAME` iv_value = lv_vsrd
                          CHANGING  cs_data = <ls_ver> ).
      ENDLOOP.
    ENDLOOP.

    IF lv_nsrv = 0.
      log( iv_kind = 'SRVB' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `nicht moeglich` e = `not possible` )
           iv_text   = lcl_t=>ui( d = `kein Service im Dokument`
                                  e = `no service in the document` ) ).
      RETURN.
    ENDIF.

    IF mv_test = abap_true.
      DATA lv_nver TYPE i.
      LOOP AT lt_rows TRANSPORTING NO FIELDS WHERE tag = 'SRVB_VER'.
        lv_nver = lv_nver + 1.
      ENDLOOP.
      log( iv_kind = 'SRVB' iv_name = iv_name
           iv_action = COND #( WHEN lv_ex = abap_true
                               THEN lcl_t=>ui( d = `wuerde geaendert` e = `would change` )
                               ELSE lcl_t=>ui( d = `wuerde angelegt` e = `would create` ) )
           iv_text   = |{ lv_btype } { lv_bver }, | &&
                       |{ lv_nsrv } | &&
                       |{ lcl_t=>ui( d = `Services` e = `services` ) }, | &&
                       |{ lv_nver } { lcl_t=>ui( d = `Versionen` e = `versions` ) }| ).
      RETURN.
    ENDIF.

    DATA(lv_desc) = lcl_attr=>value( it_attrs = lt_head iv_name = 'DESCRIPTION' ).
    IF lv_desc IS INITIAL.
      lv_desc = iv_name.
    ENDIF.

    IF mv_pack NP '$*'.
      lv_corr = mv_tr.
    ENDIF.

    TRY.
        lo_data = lcl_wb=>new_data( iv_class = 'CL_SRVB_OBJECT_DATA'
                                    iv_name  = iv_name
                                    iv_desc  = lv_desc ).
*       Nur der Inhalt wird gesetzt. Das Veroeffentlichungskennzeichen
*       bleibt aus: ein Binding anzulegen ist eine Entwicklungsaufgabe,
*       einen Dienst nach aussen bereitzustellen eine andere.
        lcl_wb=>set_content( io_data = lo_data is_content = <ls_content> ).
        lo_op = lcl_wb=>operator( iv_type = 'SRVB'
                                  iv_name = iv_name
                                  iv_corr = lv_corr ).
        lcl_wb=>save( io_op      = lo_op
                      io_data    = lo_data
                      iv_update  = lv_ex
                      iv_package = mv_pack ).
      CATCH cx_root INTO DATA(lx_put).
        log( iv_kind = 'SRVB' iv_name = iv_name
             iv_action = lcl_t=>ui( d = `Fehler` e = `error` )
             iv_text   = lx_put->get_text( ) ).
        RETURN.
    ENDTRY.

    IF mv_act = abap_true.
      TRY.
          lcl_wb=>activate( lo_op ).
        CATCH cx_root INTO DATA(lx_act).
          log( iv_kind = 'SRVB' iv_name = iv_name
               iv_action = lcl_t=>ui( d = `angelegt, inaktiv` e = `created, inactive` )
               iv_text   = lx_act->get_text( ) ).
          RETURN.
      ENDTRY.
    ENDIF.

    log( iv_kind = 'SRVB' iv_name = iv_name
         iv_action = COND #( WHEN lv_ex = abap_true
                             THEN lcl_t=>ui( d = `geaendert` e = `changed` )
                             ELSE lcl_t=>ui( d = `angelegt` e = `created` ) )
         iv_text   = |{ lv_btype } { lv_bver }, | &&
                     |{ lv_nsrv } | &&
                     |{ lcl_t=>ui( d = `Services, nicht veroeffentlicht`
                                   e = `services, not published` ) }| ).

  ENDMETHOD.

  METHOD put_wbsrc.

*   Das Gegenstueck zu def_wbsrc. Das Datenmodell wird ueber seinen
*   Klassennamen erzeugt, mit Name, Beschreibung und Quelltext gefuellt
*   und dem Operator uebergeben. Die Beschreibung muss gesetzt sein -
*   ohne sie lehnt create( ) ab.
    DATA lo_data TYPE REF TO object.
    DATA lo_op   TYPE REF TO object.
    DATA lv_corr TYPE trkorr.

    DATA(lv_ex) = exists( iv_kind = iv_kind iv_name = iv_name ).
    IF lv_ex = abap_true AND mv_over = abap_false.
      log( iv_kind = iv_kind iv_name = iv_name
           iv_action = lcl_t=>ui( d = `uebersprungen` e = `skipped` )
           iv_text   = lcl_t=>ui( d = `existiert bereits` e = `already exists` ) ).
      RETURN.
    ENDIF.

    DATA(lv_source) = io_chapter->get_defsource( ).
    IF lv_source IS INITIAL.
      log( iv_kind = iv_kind iv_name = iv_name
           iv_action = lcl_t=>ui( d = `nicht moeglich` e = `not possible` )
           iv_text   = lcl_t=>ui( d = `kein Quelltext im Dokument`
                                  e = `no source in the document` ) ).
      RETURN.
    ENDIF.

    IF mv_test = abap_true.
      DATA lt_l TYPE STANDARD TABLE OF string WITH EMPTY KEY.
      SPLIT lv_source AT cl_abap_char_utilities=>newline INTO TABLE lt_l.
      log( iv_kind = iv_kind iv_name = iv_name
           iv_action = COND #( WHEN lv_ex = abap_true
                               THEN lcl_t=>ui( d = `wuerde geaendert` e = `would change` )
                               ELSE lcl_t=>ui( d = `wuerde angelegt` e = `would create` ) )
           iv_text   = |{ lines( lt_l ) } { lcl_t=>ui( d = `Zeilen` e = `lines` ) }| ).
      RETURN.
    ENDIF.

    DATA(lv_cls)  = lcl_wb=>data_class( CONV trobjtype( iv_kind ) ).
    DATA(ls_type) = lcl_wb=>obj_type( CONV trobjtype( iv_kind ) ).
    IF lv_cls IS INITIAL OR ls_type-objtype_tr IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lv_desc) = lcl_attr=>value( it_attrs = io_chapter->get_defhead( )
                                     iv_name  = 'DESCRIPTION' ).
*   Bei einer Service-Definition liefert das Datenmodell keine
*   Beschreibung - sie steht als Annotation im Quelltext selbst. Ohne
*   Beschreibung lehnt create( ) ab, also wird sie von dort geholt.
    IF lv_desc IS INITIAL.
      FIND FIRST OCCURRENCE OF REGEX `@EndUserText\.label\s*:\s*'([^']*)'`
        IN lv_source RESULTS DATA(ls_lbl) ##REGEX_POSIX.
      IF sy-subrc = 0.
        READ TABLE ls_lbl-submatches INTO DATA(ls_sub) INDEX 1.
        IF sy-subrc = 0.
          lv_desc = substring( val = lv_source
                               off = ls_sub-offset
                               len = ls_sub-length ).
        ENDIF.
      ENDIF.
    ENDIF.
    IF lv_desc IS INITIAL.
      lv_desc = iv_name.
    ENDIF.

    IF mv_pack NP '$*'.
      lv_corr = mv_tr.
    ENDIF.

    TRY.
        lo_data = lcl_wb=>new_data( iv_class = lv_cls
                                    iv_name  = iv_name
                                    iv_desc  = lv_desc ).
        lcl_wb=>set_source( io_data = lo_data iv_source = lv_source ).
        lo_op = lcl_wb=>operator( iv_type = CONV trobjtype( iv_kind )
                                  iv_name = iv_name
                                  iv_corr = lv_corr ).
        lcl_wb=>save( io_op      = lo_op
                      io_data    = lo_data
                      iv_update  = lv_ex
                      iv_package = mv_pack ).
      CATCH cx_root INTO DATA(lx_put).
        log( iv_kind = iv_kind iv_name = iv_name
             iv_action = lcl_t=>ui( d = `Fehler` e = `error` )
             iv_text   = lx_put->get_text( ) ).
        RETURN.
    ENDTRY.

    IF mv_act = abap_true.
      TRY.
          lcl_wb=>activate( lo_op ).
        CATCH cx_root INTO DATA(lx_act).
          log( iv_kind = iv_kind iv_name = iv_name
               iv_action = lcl_t=>ui( d = `angelegt, inaktiv` e = `created, inactive` )
               iv_text   = lx_act->get_text( ) ).
          RETURN.
      ENDTRY.
    ENDIF.

    log( iv_kind = iv_kind iv_name = iv_name
         iv_action = COND #( WHEN lv_ex = abap_true
                             THEN lcl_t=>ui( d = `geaendert` e = `changed` )
                             ELSE lcl_t=>ui( d = `angelegt` e = `created` ) ) ).

  ENDMETHOD.

  METHOD put_sfpi.
*   Gegenstueck zu def_sfpi: die Schnittstelle wird ueber die Form-
*   Workbench angelegt (oder, wenn sie schon da ist, im Schreibmodus
*   geladen) und mit den Definitionsdaten gefuellt. Standardparameter
*   verwaltet das System selbst. Paket und Auftrag reichen create( )
*   selbst durch - kein eigener TADIR-Eintrag noetig.
    DATA lo_wb     TYPE REF TO if_fp_wb_interface.
    DATA lo_ifc    TYPE REF TO if_fp_interface.
    DATA lv_corr   TYPE trkorr.
    DATA lv_fpname TYPE fpname.

    DATA(lv_ex) = sfp_exists( iv_kind = 'SFPI' iv_name = iv_name ).
    IF lv_ex = abap_true AND mv_over = abap_false.
      log( iv_kind = 'SFPI' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `uebersprungen` e = `skipped` )
           iv_text   = lcl_t=>ui( d = `existiert bereits` e = `already exists` ) ).
      RETURN.
    ENDIF.

    IF mv_test = abap_true.
      log( iv_kind = 'SFPI' iv_name = iv_name
           iv_action = COND #( WHEN lv_ex = abap_true
                               THEN lcl_t=>ui( d = `wuerde geaendert` e = `would change` )
                               ELSE lcl_t=>ui( d = `wuerde angelegt` e = `would create` ) ) ).
      RETURN.
    ENDIF.

    IF mv_pack NP '$*'.
      lv_corr = mv_tr.
    ENDIF.
    lv_fpname = iv_name.

    TRY.
        IF lv_ex = abap_true.
          lo_wb = cl_fp_wb_interface=>load( i_name     = lv_fpname
                                            i_mode     = if_fp_wb_object=>c_mode_write
                                            i_ordernum = lv_corr ).
          lo_ifc ?= lo_wb->if_fp_wb_object~get_object( ).
        ELSE.
*         create( ) verlangt ein Schnittstellenobjekt - ein frisches,
*         leeres vom richtigen Typ wird angelegt und danach ueber die
*         Setter gefuellt.
          DATA lv_iftype TYPE fpinterfacetype.
          lv_iftype = lcl_attr=>value( it_attrs = io_chapter->get_defhead( )
                                       iv_name  = 'IFTYPE' ).
          lo_ifc = cl_fp_interface=>create( i_interface_type = lv_iftype ).
          lo_wb  = cl_fp_wb_interface=>create( i_name      = lv_fpname
                                               i_interface = lo_ifc
                                               i_devclass  = mv_pack
                                               i_ordernum  = lv_corr ).
        ENDIF.
        DATA(lo_id) = lo_ifc->get_interface_data( ).

*       Alle Zeilentabellen aus den Definitionszeilen aufbauen. Konkrete
*       Zeilentypen (kein generisches to_struct), damit die Belegung so
*       typsicher laeuft wie bei den DDIC-Importen.
        DATA lt_i  TYPE tfpiopar.
        DATA lt_e  TYPE tfpiopar.
        DATA lt_t  TYPE tfpiopar.
        DATA lt_x  TYPE tfpiopar.
        DATA lt_gd TYPE tfpgdata.
        DATA lt_fs TYPE tfpgdata.
        DATA lt_ci TYPE tfpparameter.
        DATA lt_co TYPE tfpparameter.
        DATA ls_iopar TYPE sfpiopar.
        DATA ls_gdata TYPE sfpgdata.
        DATA ls_cparm LIKE LINE OF lt_ci.
        DATA(lt_rows) = io_chapter->get_defrows( ).
        LOOP AT lt_rows INTO DATA(ls_r).
          CASE ls_r-tag.
            WHEN 'PAR_I' OR 'PAR_E' OR 'PAR_T' OR 'PAR_X'.
              CLEAR ls_iopar.
              lcl_attr=>to_struct( EXPORTING it_attrs = ls_r-attrs CHANGING cs_data = ls_iopar ).
              CASE ls_r-tag.
                WHEN 'PAR_I'. APPEND ls_iopar TO lt_i.
                WHEN 'PAR_E'. APPEND ls_iopar TO lt_e.
                WHEN 'PAR_T'. APPEND ls_iopar TO lt_t.
                WHEN 'PAR_X'. APPEND ls_iopar TO lt_x.
              ENDCASE.
            WHEN 'GDATA' OR 'FSYM'.
              CLEAR ls_gdata.
              lcl_attr=>to_struct( EXPORTING it_attrs = ls_r-attrs CHANGING cs_data = ls_gdata ).
              IF ls_r-tag = 'GDATA'.
                APPEND ls_gdata TO lt_gd.
              ELSE.
                APPEND ls_gdata TO lt_fs.
              ENDIF.
            WHEN 'CP_IN' OR 'CP_OUT'.
              CLEAR ls_cparm.
              lcl_attr=>to_struct( EXPORTING it_attrs = ls_r-attrs CHANGING cs_data = ls_cparm ).
              IF ls_r-tag = 'CP_IN'.
                APPEND ls_cparm TO lt_ci.
              ELSE.
                APPEND ls_cparm TO lt_co.
              ENDIF.
          ENDCASE.
        ENDLOOP.

        DATA(lo_par) = lo_id->get_parameters( ).
        lo_par->set_import_parameters( lt_i ).
        lo_par->set_export_parameters( lt_e ).
        lo_par->set_table_parameters( lt_t ).
        lo_par->set_exceptions( lt_x ).

        DATA(lo_gd) = lo_id->get_global_definitions( ).
        lo_gd->set_global_data( lt_gd ).
        lo_gd->set_fieldsymbols( lt_fs ).
        lo_gd->set_types( sfp_code_row( io_chapter = io_chapter iv_tag = 'C_TYPES' ) ).

        DATA(lo_code) = lo_id->get_coding( ).
        lo_code->set_init_coding( sfp_code_row( io_chapter = io_chapter iv_tag = 'C_INIT' ) ).
        lo_code->set_forms_coding( sfp_code_row( io_chapter = io_chapter iv_tag = 'C_FORMS' ) ).
        lo_code->set_init_input_params( lt_ci ).
        lo_code->set_init_output_params( lt_co ).

        lo_wb->if_fp_wb_object~save( ).
*       Die eigene Sperre VOR dem Aktivieren freigeben - sonst blockiert
*       der Lauf sich selbst ("Benutzer bearbeitet bereits ..."). Aktiviert
*       wird ueber die statische Methode, wie in CL_FP_WB_*=>COPY.
        lo_wb->if_fp_wb_object~free( ).
        IF mv_act = abap_true.
          cl_fp_wb_interface=>activate( i_name = lv_fpname i_ordernum = lv_corr ).
        ENDIF.
      CATCH cx_root INTO DATA(lx_put).
        log( iv_kind = 'SFPI' iv_name = iv_name
             iv_action = lcl_t=>ui( d = `Fehler` e = `error` )
             iv_text   = lx_put->get_text( ) ).
        RETURN.
    ENDTRY.

    log( iv_kind = 'SFPI' iv_name = iv_name
         iv_action = COND #( WHEN lv_ex = abap_true
                             THEN lcl_t=>ui( d = `geaendert` e = `changed` )
                             ELSE lcl_t=>ui( d = `angelegt` e = `created` ) ) ).

  ENDMETHOD.

  METHOD put_sfpf.
*   Gegenstueck zu def_sfpf. Das Formular wird nicht Knoten fuer Knoten
*   nachgebaut, sondern aus der SAP-eigenen Serialisierung wiederher-
*   gestellt - genau der Weg, den CL_FP_WB_FORM=>COPY nimmt:
*   CONVERT_XSTRING_TO_FORM, neue Layout-Kennung (das XFA-Template
*   traegt eine, die je Formular eindeutig sein muss), Schnittstellen-
*   und Handlername aus dem Klartext-Kopf neu setzen (dort greift eine
*   Umbenennung, in der Serialisierung nicht), dann ueber die Form-
*   Workbench anlegen, sichern, aktivieren. Ein vorhandenes Formular
*   wird beim Ueberschreiben geloescht und neu angelegt - in einen
*   bestehenden Workbench-Handle laesst sich kein anderes Formular-
*   objekt einhaengen.
    DATA lo_wb     TYPE REF TO if_fp_wb_form.
    DATA lo_form   TYPE REF TO if_fp_form.
    DATA lv_corr   TYPE trkorr.
    DATA lv_fpname TYPE fpname.
    DATA lv_ifname TYPE fpname.
    DATA lv_offh   TYPE seoclsname.
    DATA lv_blob   TYPE xstring.

    DATA(lv_ex) = sfp_exists( iv_kind = 'SFPF' iv_name = iv_name ).
    IF lv_ex = abap_true AND mv_over = abap_false.
      log( iv_kind = 'SFPF' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `uebersprungen` e = `skipped` )
           iv_text   = lcl_t=>ui( d = `existiert bereits` e = `already exists` ) ).
      RETURN.
    ENDIF.

*   Ohne die Serialisierung gibt es nichts anzulegen.
    DATA(lt_rows) = io_chapter->get_defrows( ).
    READ TABLE lt_rows INTO DATA(ls_blob) WITH KEY tag = 'FORM_DATA'.
    IF sy-subrc <> 0 OR ls_blob-src IS INITIAL.
      log( iv_kind = 'SFPF' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `Fehler` e = `error` )
           iv_text   = lcl_t=>ui( d = `Keine Formulardaten (FORM_DATA) in den Definitionsdaten.`
                                  e = `No form data (FORM_DATA) in the definition data.` ) ).
      RETURN.
    ENDIF.

    IF mv_test = abap_true.
      log( iv_kind = 'SFPF' iv_name = iv_name
           iv_action = COND #( WHEN lv_ex = abap_true
                               THEN lcl_t=>ui( d = `wuerde geaendert` e = `would change` )
                               ELSE lcl_t=>ui( d = `wuerde angelegt` e = `would create` ) ) ).
      RETURN.
    ENDIF.

    IF mv_pack NP '$*'.
      lv_corr = mv_tr.
    ENDIF.
    lv_fpname = iv_name.
    DATA(lt_head) = io_chapter->get_defhead( ).
    lv_ifname = lcl_attr=>value( it_attrs = lt_head iv_name = 'INTERFACE' ).
    lv_offh   = lcl_attr=>value( it_attrs = lt_head iv_name = 'OFFLINE_HANDLER' ).

    TRY.
        lv_blob = cl_http_utility=>decode_x_base64( encoded = ls_blob-src ).
        lo_form = cl_fp_helper=>convert_xstring_to_form( i_xstring  = lv_blob
                                                         i_language = sy-langu ).
        cl_fp_helper=>set_new_layout_id( CHANGING c_form = lo_form ).
        IF lv_ifname IS NOT INITIAL.
          lo_form->set_interface_name( lv_ifname ).
        ENDIF.
        IF lv_offh IS NOT INITIAL.
          lo_form->set_offline_handler( lv_offh ).
        ENDIF.

        IF lv_ex = abap_true.
          cl_fp_wb_form=>delete( i_name     = lv_fpname
                                 i_ordernum = lv_corr ).
        ENDIF.
        lo_wb = cl_fp_wb_form=>create( i_name     = lv_fpname
                                       i_form     = lo_form
                                       i_devclass = mv_pack
                                       i_ordernum = lv_corr ).
        lo_wb->if_fp_wb_object~save( ).
*       Eigene Sperre VOR dem Aktivieren freigeben (sonst Selbstblockade),
*       dann statisch aktivieren - wie in CL_FP_WB_*=>COPY.
        lo_wb->if_fp_wb_object~free( ).
        IF mv_act = abap_true.
          cl_fp_wb_form=>activate( i_name = lv_fpname i_ordernum = lv_corr ).
        ENDIF.
      CATCH cx_root INTO DATA(lx_put).
        log( iv_kind = 'SFPF' iv_name = iv_name
             iv_action = lcl_t=>ui( d = `Fehler` e = `error` )
             iv_text   = lx_put->get_text( ) ).
        RETURN.
    ENDTRY.

    log( iv_kind = 'SFPF' iv_name = iv_name
         iv_action = COND #( WHEN lv_ex = abap_true
                             THEN lcl_t=>ui( d = `geaendert` e = `changed` )
                             ELSE lcl_t=>ui( d = `angelegt` e = `created` ) ) ).

  ENDMETHOD.

  METHOD sfp_exists.
*   Ein Katalogeintrag beweist bei Formularobjekten nichts - massgeblich
*   ist, ob die Workbench das Objekt laedt. Im Lesemodus ohne Sperre.
    DATA lv_fpname TYPE fpname.
    lv_fpname = iv_name.
    TRY.
        IF iv_kind = 'SFPF'.
          DATA(lo_f) = cl_fp_wb_form=>load( i_name = lv_fpname
                                            i_mode = if_fp_wb_object=>c_mode_read ).
          rv_flag = boolc( lo_f IS BOUND ).
        ELSE.
          DATA(lo_i) = cl_fp_wb_interface=>load( i_name = lv_fpname
                                                 i_mode = if_fp_wb_object=>c_mode_read ).
          rv_flag = boolc( lo_i IS BOUND ).
        ENDIF.
      CATCH cx_root.
        CLEAR rv_flag.
    ENDTRY.
  ENDMETHOD.

  METHOD sfp_code_row.
*   Ein als src abgelegter Coding-Block wird wieder in eine Zeilentabelle
*   zerlegt. Fehlt der Block, bleibt die Tabelle leer.
    DATA(lt_rows) = io_chapter->get_defrows( ).
    READ TABLE lt_rows INTO DATA(ls_row) WITH KEY tag = iv_tag.
    IF sy-subrc <> 0 OR ls_row-src IS INITIAL.
      RETURN.
    ENDIF.
    SPLIT ls_row-src AT cl_abap_char_utilities=>newline INTO TABLE rt_code.
  ENDMETHOD.

  METHOD put_msag.

    DATA lt_t100 TYPE STANDARD TABLE OF t100 WITH EMPTY KEY.
    DATA ls_head TYPE t100a.

    DATA(lv_ex) = exists( iv_kind = 'MSAG' iv_name = iv_name ).
    IF lv_ex = abap_true AND mv_over = abap_false.
      log( iv_kind = 'MSAG' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `uebersprungen` e = `skipped` )
           iv_text   = lcl_t=>ui( d = `existiert bereits` e = `already exists` ) ).
      RETURN.
    ENDIF.

    lcl_attr=>to_struct( EXPORTING it_attrs = io_chapter->get_defhead( )
                         CHANGING  cs_data  = ls_head ).
    ls_head-arbgb = iv_name.

    LOOP AT io_chapter->get_defrows( ) INTO DATA(ls_row) WHERE tag = 'T100'.
      DATA ls_t100 TYPE t100.
      CLEAR ls_t100.
      lcl_attr=>to_struct( EXPORTING it_attrs = ls_row-attrs
                           CHANGING  cs_data  = ls_t100 ).
      ls_t100-arbgb = iv_name.
      APPEND ls_t100 TO lt_t100.
    ENDLOOP.

    IF lt_t100 IS INITIAL.
      log( iv_kind = 'MSAG' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `nicht moeglich` e = `not possible` )
           iv_text   = lcl_t=>ui( d = `keine Nachrichten im Dokument`
                                  e = `no messages in the document` ) ).
      RETURN.
    ENDIF.

    IF mv_test = abap_true.
      log( iv_kind = 'MSAG' iv_name = iv_name
           iv_action = COND #( WHEN lv_ex = abap_true
                               THEN lcl_t=>ui( d = `wuerde ergaenzt` e = `would be extended` )
                               ELSE lcl_t=>ui( d = `wuerde angelegt` e = `would create` ) )
           iv_text   = |{ lines( lt_t100 ) } { lcl_t=>ui( d = `Nachrichten` e = `messages` ) }| ).
      RETURN.
    ENDIF.

*   Written to T100A and T100 directly. RPY_MESSAGE_ID_INSERT would be
*   the API, but it opens the object catalog popup - "Objektkatalog-
*   eintrag anlegen" - even with $TMP as the package, and an unattended
*   import cannot answer a dialog. T100A and T100 are where SE91 keeps
*   the class; the catalog entry is written by the same helper that
*   every other object type here uses.
    ls_head-lastuser = sy-uname.
    ls_head-ldate    = sy-datum.
    ls_head-ltime    = sy-uzeit.
    IF ls_head-masterlang IS INITIAL.
      ls_head-masterlang = sy-langu.
    ENDIF.
    MODIFY t100a FROM ls_head.

*   Existing texts are not touched. Somebody may have translated or
*   corrected them here, and a documentation tool has no business
*   overwriting that; missing numbers and missing languages are added.
    DATA lv_add TYPE i.
    LOOP AT lt_t100 INTO ls_t100.
      SELECT COUNT(*) FROM t100 WHERE sprsl = @ls_t100-sprsl AND arbgb = @ls_t100-arbgb AND msgnr = @ls_t100-msgnr.
      DATA(lv_there) = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).
      IF lv_there = abap_true.
        CONTINUE.
      ENDIF.
      INSERT t100 FROM ls_t100.
      IF sy-subrc = 0.
        lv_add = lv_add + 1.
      ENDIF.
    ENDLOOP.

    tadir( iv_object = 'MSAG' iv_name = CONV sobj_name( iv_name ) ).

    log( iv_kind = 'MSAG' iv_name = iv_name
         iv_action = COND #( WHEN lv_ex = abap_true
                             THEN lcl_t=>ui( d = `ergaenzt` e = `extended` )
                             ELSE lcl_t=>ui( d = `angelegt` e = `created` ) )
         iv_text   = |{ lv_add } { lcl_t=>ui( d = `Nachrichten neu von`
                                              e = `messages added of` ) } | &&
                     |{ lines( lt_t100 ) }| ).

  ENDMETHOD.

  METHOD put_dynp.

*   Das Gegenstueck zu def_dynp. Kopf, Container, Felder und Parameter
*   kommen aus den Zeilen zurueck, die Ablauflogik aus dem Quelltext
*   der DYNP-Zeile.
    DATA ls_head TYPE rpy_dyhead.
    DATA lt_cont TYPE dycatt_tab.
    DATA lt_f2c  TYPE dyfatc_tab.
*   DYN_FLOWLIST, nicht RPY_DYFLOW, obwohl die Schnittstelle RPY_DYFLOW
*   deklariert: beide Bausteine reichen die Ablauflogik unveraendert an
*   ihr NATIVE-Gegenstueck weiter, und dessen Parameter ist mit dem
*   Tabellentyp DYN_FLOWLIST typisiert. Ein Aktualparameter, der dazu
*   nicht typkompatibel ist - andere Zeile oder anderer Schluessel -
*   endet dort im Kurzdump CALL_FUNCTION_CONFLICT_TAB_TYP.
    DATA lt_flow TYPE dyn_flowlist.
    DATA lt_para TYPE STANDARD TABLE OF rpy_dypara WITH EMPTY KEY.
    DATA ls_cont TYPE rpy_dycatt.
    DATA ls_f2c  TYPE rpy_dyfatc.
    DATA ls_para TYPE rpy_dypara.
    DATA ls_flow TYPE d022s.
    DATA lt_line TYPE STANDARD TABLE OF string WITH EMPTY KEY.
    DATA lv_corr TYPE e071-trkorr.
    DATA lv_dnr  TYPE string.
    DATA lv_n    TYPE i.
    DATA lv_bad  TYPE i.

    DATA(lt_rows) = io_chapter->get_defrows( ).
    IF mv_pack NP '$*'.
      lv_corr = mv_tr.
    ENDIF.

    LOOP AT lt_rows INTO DATA(ls_row) WHERE tag = 'DYNP'.

      CLEAR: ls_head, lt_cont, lt_f2c, lt_flow, lt_para.
      lcl_attr=>to_struct( EXPORTING it_attrs = ls_row-attrs
                           CHANGING  cs_data  = ls_head ).
      IF ls_head-screen IS INITIAL.
        CONTINUE.
      ENDIF.

*     Der Kopf traegt den Programmnamen des Quellsystems. Er wird hier
*     ueberschrieben - die Gruppe kann drueben anders heissen.
      ls_head-program = iv_prog.
      lv_dnr = ls_head-screen.

      CLEAR lt_line.
      SPLIT ls_row-src AT cl_abap_char_utilities=>newline INTO TABLE lt_line.
      LOOP AT lt_line INTO DATA(lv_line).
        CLEAR ls_flow.
        ls_flow-line = lv_line.
        APPEND ls_flow TO lt_flow.
      ENDLOOP.

      LOOP AT lt_rows INTO DATA(ls_p).
        IF lcl_attr=>value( it_attrs = ls_p-attrs iv_name = '_DYNNR' ) <> lv_dnr.
          CONTINUE.
        ENDIF.
        CASE ls_p-tag.
          WHEN 'DYCAT'.
            CLEAR ls_cont.
            lcl_attr=>to_struct( EXPORTING it_attrs = ls_p-attrs CHANGING cs_data = ls_cont ).
            APPEND ls_cont TO lt_cont.
          WHEN 'DYFAT'.
            CLEAR ls_f2c.
            lcl_attr=>to_struct( EXPORTING it_attrs = ls_p-attrs CHANGING cs_data = ls_f2c ).
            APPEND ls_f2c TO lt_f2c.
          WHEN 'DYPARA'.
            CLEAR ls_para.
            lcl_attr=>to_struct( EXPORTING it_attrs = ls_p-attrs CHANGING cs_data = ls_para ).
            APPEND ls_para TO lt_para.
        ENDCASE.
      ENDLOOP.

      IF mv_test = abap_true.
        lv_n = lv_n + 1.
        CONTINUE.
      ENDIF.

      CALL FUNCTION 'RPY_DYNPRO_INSERT'
        EXPORTING  suppress_corr_checks   = abap_true
                   corrnum                = lv_corr
                   suppress_exist_checks  = abap_true
                   header                 = ls_head
        TABLES     containers             = lt_cont
                   fields_to_containers   = lt_f2c
                   flow_logic             = lt_flow
                   params                 = lt_para
        EXCEPTIONS cancelled              = 1
                   already_exists         = 2
                   program_not_exists     = 3
                   not_executed           = 4
                   missing_required_field = 5
                   illegal_field_value    = 6
                   field_not_allowed      = 7
                   not_generated          = 8
                   illegal_field_position = 9
                   OTHERS                 = 10.
      CASE sy-subrc.
        WHEN 0.
          lv_n = lv_n + 1.
        WHEN 2.
*         Ein vorhandenes Dynpro wird nicht ueberschrieben. Der
*         Baustein kennt keinen Weg dazu, der ohne SE51 auskommt.
          log( iv_kind = 'DYNP' iv_name = |{ iv_prog } { lv_dnr }|
               iv_action = lcl_t=>ui( d = `uebersprungen` e = `skipped` )
               iv_text   = lcl_t=>ui( d = `existiert bereits`
                                      e = `already exists` ) ).
        WHEN OTHERS.
          lv_bad = lv_bad + 1.
          DATA(lv_rc8) = sy-subrc.
          DATA(lv_msg8) = last_message( ).
          log( iv_kind = 'DYNP' iv_name = |{ iv_prog } { lv_dnr }|
               iv_action = lcl_t=>ui( d = `Fehler` e = `error` )
               iv_text   = |RPY_DYNPRO_INSERT subrc { lv_rc8 } { lv_msg8 }| ).
      ENDCASE.

    ENDLOOP.

    IF lv_n = 0 AND lv_bad = 0.
      RETURN.
    ENDIF.

    log( iv_kind = 'DYNP' iv_name = CONV string( iv_prog )
         iv_action = COND #( WHEN mv_test = abap_true
                             THEN lcl_t=>ui( d = `wuerde anlegen` e = `would create` )
                             ELSE lcl_t=>ui( d = `angelegt` e = `created` ) )
         iv_text   = |{ lv_n } { lcl_t=>ui( d = `Bilder` e = `screens` ) }| ).

  ENDMETHOD.

  METHOD put_maint.

*   Der Pflegeeintrag zu View oder Tabelle. TVDIR, TVIMF und TDDAT
*   werden direkt geschrieben: SE54 ist der einzige Weg, sie erzeugen
*   zu lassen, und SE54 ist ein Dialog.
*
*   Die drei Tabellen sind mandantenunabhaengig und haengen nicht am
*   Transportauftrag - der Eintrag entsteht im Zielsystem also lokal.
*   Das Protokoll sagt es, damit niemand ihn im Auftrag sucht.
    DATA ls_tvdir TYPE tvdir.
    DATA ls_tvimf TYPE tvimf.
    DATA ls_tddat TYPE tddat.
    DATA lt_tvimf TYPE STANDARD TABLE OF tvimf WITH EMPTY KEY.
    DATA lv_tab   TYPE tvdir-tabname.
    DATA lv_has   TYPE abap_bool.

    DATA(lt_rows) = io_chapter->get_defrows( ).
    READ TABLE lt_rows TRANSPORTING NO FIELDS WITH KEY tag = 'TVDIR'.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    LOOP AT lt_rows INTO DATA(ls_row).
      CASE ls_row-tag.
        WHEN 'TVDIR'.
          lcl_attr=>to_struct( EXPORTING it_attrs = ls_row-attrs CHANGING cs_data = ls_tvdir ).
          lv_has = abap_true.
        WHEN 'TVIMF'.
          CLEAR ls_tvimf.
          lcl_attr=>to_struct( EXPORTING it_attrs = ls_row-attrs CHANGING cs_data = ls_tvimf ).
          APPEND ls_tvimf TO lt_tvimf.
        WHEN 'TDDAT'.
          lcl_attr=>to_struct( EXPORTING it_attrs = ls_row-attrs CHANGING cs_data = ls_tddat ).
      ENDCASE.
    ENDLOOP.

    IF lv_has = abap_false OR ls_tvdir-tabname IS INITIAL.
      RETURN.
    ENDIF.
    lv_tab = ls_tvdir-tabname.

    IF mv_test = abap_true.
      log( iv_kind = 'TVDIR' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `wuerde anlegen` e = `would create` )
           iv_text   = |{ lcl_t=>ui( d = `Pflegedialog` e = `maintenance dialog` ) }, | &&
                       |{ lcl_t=>ui( d = `Gruppe` e = `group` ) } { ls_tvdir-area }, | &&
                       |{ ls_tvdir-liste }/{ ls_tvdir-detail }| ).
      RETURN.
    ENDIF.

*   Die Funktionsgruppe muss stehen, sonst zeigt der Eintrag ins Leere
*   und SM30 laeuft in einen Kurzdump statt in eine Meldung.
    SELECT COUNT(*) FROM tlibg WHERE area = @ls_tvdir-area.
    DATA(lv_fugr) = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).
    IF lv_fugr <> abap_true.
      log( iv_kind = 'TVDIR' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `nicht geschrieben` e = `not written` )
           iv_text   = |{ lcl_t=>ui( d = `Funktionsgruppe fehlt`
                                     e = `function group missing` ) }: { ls_tvdir-area }| ).
      RETURN.
    ENDIF.

    MODIFY tvdir FROM ls_tvdir.
    IF sy-subrc <> 0.
      DATA(lv_rc9) = sy-subrc.
      DATA(lv_msg9) = last_message( ).
      log( iv_kind = 'TVDIR' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `Fehler` e = `error` )
           iv_text   = |MODIFY tvdir subrc { lv_rc9 } { lv_msg9 }| ).
      RETURN.
    ENDIF.

    DELETE FROM tvimf WHERE tabname = @lv_tab.
    IF lt_tvimf IS NOT INITIAL.
      INSERT tvimf FROM TABLE @lt_tvimf.
    ENDIF.

    IF ls_tddat-tabname IS NOT INITIAL.
      MODIFY tddat FROM ls_tddat.
    ENDIF.

    log( iv_kind = 'TVDIR' iv_name = iv_name
         iv_action = lcl_t=>ui( d = `angelegt` e = `created` )
         iv_text   = |{ lcl_t=>ui( d = `Gruppe` e = `group` ) } { ls_tvdir-area }, | &&
                     |{ lines( lt_tvimf ) } { lcl_t=>ui( d = `Ereignisse` e = `events` ) }, | &&
                     |{ lcl_t=>ui( d = `lokal, nicht im Auftrag`
                                   e = `local, not in the request` ) }| ).

  ENDMETHOD.

  METHOD put_tran.

*   RPY_TRANSACTION_INSERT legt zwei Arten an: die Dialogtransaktion
*   auf Programm und Dynpro, und die Parametertransaktion, die eine
*   andere Transaktion mit vorbelegten Feldern ruft. Der Pflegedialog
*   ist fast immer der zweite Fall - SM30 mit gesetztem VIEWNAME.
    DATA ls_tstc  TYPE tstc.
    DATA ls_tstcc TYPE tstcc.
    DATA lt_par   TYPE STANDARD TABLE OF rsparam WITH EMPTY KEY.
    DATA ls_par   TYPE rsparam.
    DATA lv_corr  TYPE rglif-trkorr.
    DATA lv_call  TYPE tstc-tcode.
    DATA lv_skip  TYPE c LENGTH 1.
    DATA lv_type  TYPE rglif-docutype.
    DATA lv_param TYPE string.
    DATA lv_lang  TYPE sy-langu.

    DATA(lv_ex) = exists( iv_kind = 'TRAN' iv_name = iv_name ).
    IF lv_ex = abap_true AND mv_over = abap_false.
      log( iv_kind = 'TRAN' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `uebersprungen` e = `skipped` )
           iv_text   = lcl_t=>ui( d = `existiert bereits` e = `already exists` ) ).
      RETURN.
    ENDIF.

    DATA(lt_head) = io_chapter->get_defhead( ).
    lcl_attr=>to_struct( EXPORTING it_attrs = lt_head CHANGING cs_data = ls_tstc ).
    IF ls_tstc-tcode IS INITIAL.
      RETURN.
    ENDIF.
    DATA(lv_text) = lcl_attr=>value( it_attrs = lt_head iv_name = 'SHORT_TEXT' ).

*   Der Kurztext wurde in der Ausgabesprache des Dokuments gelesen. Er
*   unter der Anmeldesprache anzulegen wuerde ihn falsch beschriften.
    DATA(lv_dlan) = io_chapter->get_doclang( ).
    lv_lang = COND #( WHEN lv_dlan IS NOT INITIAL THEN lv_dlan ELSE sy-langu ).

    LOOP AT io_chapter->get_defrows( ) INTO DATA(ls_row).
      CASE ls_row-tag.
        WHEN 'TSTCC'.
          lcl_attr=>to_struct( EXPORTING it_attrs = ls_row-attrs CHANGING cs_data = ls_tstcc ).
        WHEN 'TSTCP'.
          lv_param = lcl_attr=>value( it_attrs = ls_row-attrs iv_name = 'PARAM' ).
      ENDCASE.
    ENDLOOP.

*   Die Vorbelegung steht als eine Zeile in TSTCP: hinter /* die
*   gerufene Transaktion, dahinter NAME=WERT, getrennt durch ;. Das
*   fuehrende /* heisst "erstes Bild ueberspringen".
    IF lv_param IS NOT INITIAL.
      DATA lv_rest TYPE string.
      lv_rest = lv_param.
      IF strlen( lv_rest ) > 2 AND lv_rest(2) = `/*`.
        lv_skip = abap_true.
        lv_rest = lv_rest+2.
      ELSEIF strlen( lv_rest ) > 1 AND lv_rest(1) = `/`.
        lv_rest = lv_rest+1.
      ENDIF.
      SPLIT lv_rest AT ` ` INTO DATA(lv_first) lv_rest.
      lv_call = lv_first.
      SPLIT lv_rest AT `;` INTO TABLE DATA(lt_pair).
      LOOP AT lt_pair INTO DATA(lv_pair).
        IF lv_pair IS INITIAL OR lv_pair NS `=`.
          CONTINUE.
        ENDIF.
        CLEAR ls_par.
        SPLIT lv_pair AT `=` INTO DATA(lv_fld) DATA(lv_val).
        CONDENSE lv_fld.
        ls_par-field = lv_fld.
        ls_par-value = lv_val.
        APPEND ls_par TO lt_par.
      ENDLOOP.
    ENDIF.

    IF lv_call IS NOT INITIAL.
      lv_type = 'P'.
    ELSEIF ls_tstc-pgmna IS NOT INITIAL.
      lv_type = 'T'.
    ELSE.
      log( iv_kind = 'TRAN' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `uebersprungen` e = `skipped` )
           iv_text   = lcl_t=>ui( d = `weder Programm noch Vorbelegung`
                                  e = `neither program nor parameters` ) ).
      RETURN.
    ENDIF.

    IF mv_test = abap_true.
      log( iv_kind = 'TRAN' iv_name = iv_name
           iv_action = COND #( WHEN lv_ex = abap_true
                               THEN lcl_t=>ui( d = `wuerde geaendert` e = `would change` )
                               ELSE lcl_t=>ui( d = `wuerde angelegt` e = `would create` ) )
           iv_text   = COND #( WHEN lv_type = 'P'
                               THEN |{ lcl_t=>ui( d = `Parametertransaktion auf`
                                                  e = `parameter transaction on` ) } | &&
                                    |{ lv_call }, { lines( lt_par ) } | &&
                                    |{ lcl_t=>ui( d = `Werte` e = `values` ) }|
                               ELSE |{ ls_tstc-pgmna } { ls_tstc-dypno }| ) ).
      RETURN.
    ENDIF.

    IF mv_pack NP '$*'.
      lv_corr = mv_tr.
    ENDIF.

    CALL FUNCTION 'RPY_TRANSACTION_INSERT'
      EXPORTING  transaction             = ls_tstc-tcode
                 program                 = ls_tstc-pgmna
                 dynpro                  = ls_tstc-dypno
                 language                = lv_lang
                 development_class       = mv_pack
                 transport_number        = lv_corr
                 transaction_type        = lv_type
                 shorttext               = lv_text
                 called_transaction      = lv_call
                 called_transaction_skip = lv_skip
                 suppress_corr_check     = abap_true
      TABLES     param_values            = lt_par
      EXCEPTIONS cancelled               = 1
                 already_exist           = 2
                 permission_error        = 3
                 name_not_allowed        = 4
                 name_conflict           = 5
                 illegal_type            = 6
                 object_inconsistent     = 7
                 db_access_error         = 8
                 OTHERS                  = 9.
    IF sy-subrc <> 0 AND sy-subrc <> 2.
      DATA(lv_rc10) = sy-subrc.
      DATA(lv_msg10) = last_message( ).
      log( iv_kind = 'TRAN' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `Fehler` e = `error` )
           iv_text   = |RPY_TRANSACTION_INSERT subrc { lv_rc10 } { lv_msg10 }| ).
      RETURN.
    ENDIF.

*   Die GUI-Kennzeichen nimmt der Baustein nicht entgegen. Ohne sie
*   laesst sich die Transaktion im SAP GUI zwar starten, im Web aber
*   nicht - deshalb kommen sie hinterher dazu.
    IF ls_tstcc-tcode IS NOT INITIAL.
      MODIFY tstcc FROM ls_tstcc.
    ENDIF.

    log( iv_kind = 'TRAN' iv_name = iv_name
         iv_action = COND #( WHEN lv_ex = abap_true
                             THEN lcl_t=>ui( d = `geaendert` e = `changed` )
                             ELSE lcl_t=>ui( d = `angelegt` e = `created` ) )
         iv_text   = COND #( WHEN lv_type = 'P'
                             THEN |{ lv_call }, { lines( lt_par ) } | &&
                                  |{ lcl_t=>ui( d = `Werte` e = `values` ) }|
                             ELSE |{ ls_tstc-pgmna } { ls_tstc-dypno }| ) ).

  ENDMETHOD.

  METHOD put_vcls.

    DATA ls_dir TYPE v_vcldir.
    DATA lt_str TYPE STANDARD TABLE OF v_vclstruc WITH EMPTY KEY.
    DATA lt_dep TYPE STANDARD TABLE OF vclstrudep WITH EMPTY KEY.
    DATA lt_mf  TYPE STANDARD TABLE OF vclmf WITH EMPTY KEY.
    DATA ls_str TYPE v_vclstruc.
    DATA ls_dep TYPE vclstrudep.
    DATA ls_mf  TYPE vclmf.

    DATA(lv_ex) = exists( iv_kind = 'VCLS' iv_name = iv_name ).
    IF lv_ex = abap_true AND mv_over = abap_false.
      log( iv_kind = 'VCLS' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `uebersprungen` e = `skipped` )
           iv_text   = lcl_t=>ui( d = `existiert bereits` e = `already exists` ) ).
      RETURN.
    ENDIF.

    lcl_attr=>to_struct( EXPORTING it_attrs = io_chapter->get_defhead( )
                         CHANGING  cs_data  = ls_dir ).
    IF ls_dir-vclname IS INITIAL.
      RETURN.
    ENDIF.

    LOOP AT io_chapter->get_defrows( ) INTO DATA(ls_row).
      CASE ls_row-tag.
        WHEN 'VCLSTRUC'.
          CLEAR ls_str.
          lcl_attr=>to_struct( EXPORTING it_attrs = ls_row-attrs CHANGING cs_data = ls_str ).
          APPEND ls_str TO lt_str.
        WHEN 'VCLSTDEP'.
          CLEAR ls_dep.
          lcl_attr=>to_struct( EXPORTING it_attrs = ls_row-attrs CHANGING cs_data = ls_dep ).
          APPEND ls_dep TO lt_dep.
        WHEN 'VCLMF'.
          CLEAR ls_mf.
          lcl_attr=>to_struct( EXPORTING it_attrs = ls_row-attrs CHANGING cs_data = ls_mf ).
          APPEND ls_mf TO lt_mf.
      ENDCASE.
    ENDLOOP.

*   Ein Knoten ohne den View dahinter macht den Cluster unbrauchbar -
*   SM34 laeuft dann beim Aufklappen in einen Fehler. Lieber gar
*   nicht anlegen und den Fehlbestand nennen.
    DATA lv_miss TYPE string.
    LOOP AT lt_str INTO ls_str.
      IF exists( iv_kind = 'VIEW' iv_name = CONV string( ls_str-object ) ) = abap_false
         AND exists( iv_kind = 'TABL' iv_name = CONV string( ls_str-object ) ) = abap_false.
        lv_miss = COND #( WHEN lv_miss IS INITIAL THEN ls_str-object
                          ELSE |{ lv_miss }, { ls_str-object }| ).
      ENDIF.
    ENDLOOP.
    IF lv_miss IS NOT INITIAL.
      log( iv_kind = 'VCLS' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `nicht angelegt` e = `not created` )
           iv_text   = |{ lcl_t=>ui( d = `Knoten fehlen` e = `nodes missing` ) }: { lv_miss }| ).
      RETURN.
    ENDIF.

    IF mv_test = abap_true.
      log( iv_kind = 'VCLS' iv_name = iv_name
           iv_action = COND #( WHEN lv_ex = abap_true
                               THEN lcl_t=>ui( d = `wuerde geaendert` e = `would change` )
                               ELSE lcl_t=>ui( d = `wuerde angelegt` e = `would create` ) )
           iv_text   = |{ lines( lt_str ) } { lcl_t=>ui( d = `Knoten` e = `nodes` ) }| ).
      RETURN.
    ENDIF.

    CALL FUNCTION 'VIEWCLUSTER_SAVE_DEFINITION'
      EXPORTING  vcldir_entry   = ls_dir
      TABLES     vclstruc_tab   = lt_str
                 vclstrudep_tab = lt_dep
                 vclmf_tab      = lt_mf
      EXCEPTIONS OTHERS         = 1.
    IF sy-subrc <> 0.
      DATA(lv_rc11) = sy-subrc.
      DATA(lv_msg11) = last_message( ).
      log( iv_kind = 'VCLS' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `Fehler` e = `error` )
           iv_text   = |VIEWCLUSTER_SAVE_DEFINITION subrc { lv_rc11 } { lv_msg11 }| ).
      RETURN.
    ENDIF.

    tadir( iv_object = 'VCLS' iv_name = CONV sobj_name( iv_name ) ).

    log( iv_kind = 'VCLS' iv_name = iv_name
         iv_action = COND #( WHEN lv_ex = abap_true
                             THEN lcl_t=>ui( d = `geaendert` e = `changed` )
                             ELSE lcl_t=>ui( d = `angelegt` e = `created` ) )
         iv_text   = |{ lines( lt_str ) } { lcl_t=>ui( d = `Knoten` e = `nodes` ) }| ).

  ENDMETHOD.

  METHOD put_cua.

*   The counterpart to def_cua. Eleven tables come back out of the rows
*   they were written to, and RS_CUA_INTERNAL_WRITE puts them into the
*   program. Without the status a report that sets its own PF-STATUS
*   dumps at the first screen - the source alone is not the program.
    DATA lt_sta TYPE STANDARD TABLE OF rsmpe_stat WITH EMPTY KEY.
    DATA lt_fun TYPE STANDARD TABLE OF rsmpe_funt WITH EMPTY KEY.
    DATA lt_men TYPE STANDARD TABLE OF rsmpe_men  WITH EMPTY KEY.
    DATA lt_mtx TYPE STANDARD TABLE OF rsmpe_mnlt WITH EMPTY KEY.
    DATA lt_act TYPE STANDARD TABLE OF rsmpe_act  WITH EMPTY KEY.
    DATA lt_but TYPE STANDARD TABLE OF rsmpe_but  WITH EMPTY KEY.
    DATA lt_pfk TYPE STANDARD TABLE OF rsmpe_pfk  WITH EMPTY KEY.
    DATA lt_set TYPE STANDARD TABLE OF rsmpe_staf WITH EMPTY KEY.
    DATA lt_doc TYPE STANDARD TABLE OF rsmpe_atrt WITH EMPTY KEY.
    DATA lt_tit TYPE STANDARD TABLE OF rsmpe_titt WITH EMPTY KEY.
    DATA lt_biv TYPE STANDARD TABLE OF rsmpe_buts WITH EMPTY KEY.
    DATA ls_adm TYPE rsmpe_adm.
    DATA ls_key TYPE trkey.
    DATA lv_prg TYPE trdir-name.
    DATA lr_tab TYPE REF TO data.
    DATA lr_row TYPE REF TO data.

    DATA(lt_rows) = io_chapter->get_defrows( ).
    READ TABLE lt_rows INTO DATA(ls_adr) WITH KEY tag = 'CUA_ADM'.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    lcl_attr=>to_struct( EXPORTING it_attrs = ls_adr-attrs
                         CHANGING  cs_data  = ls_adm ).

    FIELD-SYMBOLS <lt_any> TYPE STANDARD TABLE.
    FIELD-SYMBOLS <ls_any> TYPE any.

    LOOP AT lt_rows INTO DATA(ls_row) WHERE tag CP 'CUA_*' AND tag <> 'CUA_ADM'.
      CASE ls_row-tag.
        WHEN 'CUA_STA'. GET REFERENCE OF lt_sta INTO lr_tab.
                        CREATE DATA lr_row TYPE rsmpe_stat.
        WHEN 'CUA_FUN'. GET REFERENCE OF lt_fun INTO lr_tab.
                        CREATE DATA lr_row TYPE rsmpe_funt.
        WHEN 'CUA_MEN'. GET REFERENCE OF lt_men INTO lr_tab.
                        CREATE DATA lr_row TYPE rsmpe_men.
        WHEN 'CUA_MTX'. GET REFERENCE OF lt_mtx INTO lr_tab.
                        CREATE DATA lr_row TYPE rsmpe_mnlt.
        WHEN 'CUA_ACT'. GET REFERENCE OF lt_act INTO lr_tab.
                        CREATE DATA lr_row TYPE rsmpe_act.
        WHEN 'CUA_BUT'. GET REFERENCE OF lt_but INTO lr_tab.
                        CREATE DATA lr_row TYPE rsmpe_but.
        WHEN 'CUA_PFK'. GET REFERENCE OF lt_pfk INTO lr_tab.
                        CREATE DATA lr_row TYPE rsmpe_pfk.
        WHEN 'CUA_SET'. GET REFERENCE OF lt_set INTO lr_tab.
                        CREATE DATA lr_row TYPE rsmpe_staf.
        WHEN 'CUA_DOC'. GET REFERENCE OF lt_doc INTO lr_tab.
                        CREATE DATA lr_row TYPE rsmpe_atrt.
        WHEN 'CUA_TIT'. GET REFERENCE OF lt_tit INTO lr_tab.
                        CREATE DATA lr_row TYPE rsmpe_titt.
        WHEN 'CUA_BIV'. GET REFERENCE OF lt_biv INTO lr_tab.
                        CREATE DATA lr_row TYPE rsmpe_buts.
        WHEN OTHERS.    CONTINUE.
      ENDCASE.
      ASSIGN lr_tab->* TO <lt_any>.
      ASSIGN lr_row->* TO <ls_any>.
      lcl_attr=>to_struct( EXPORTING it_attrs = ls_row-attrs
                           CHANGING  cs_data  = <ls_any> ).
      INSERT <ls_any> INTO TABLE <lt_any>.
    ENDLOOP.

    IF lt_sta IS INITIAL AND lt_fun IS INITIAL AND lt_tit IS INITIAL.
      RETURN.
    ENDIF.

    ls_key-devclass = mv_pack.
    ls_key-obj_type = 'PROG'.
    ls_key-obj_name = iv_prog.
    ls_key-sub_type = 'CUAD'.
    ls_key-sub_name = iv_prog.

    lv_prg = iv_prog.
    CALL FUNCTION 'RS_CUA_INTERNAL_WRITE'
      EXPORTING  program      = lv_prg
                 language     = sy-langu
                 tr_key       = ls_key
                 adm          = ls_adm
                 state        = 'A'
      TABLES     sta          = lt_sta
                 fun          = lt_fun
                 men          = lt_men
                 mtx          = lt_mtx
                 act          = lt_act
                 but          = lt_but
                 pfk          = lt_pfk
                 set          = lt_set
                 doc          = lt_doc
                 tit          = lt_tit
                 biv          = lt_biv
      EXCEPTIONS not_found    = 1
                 invalid_data = 2
                 OTHERS       = 3.
    IF sy-subrc <> 0.
      DATA(lv_rc12) = sy-subrc.
      DATA(lv_msg12) = last_message( ).
      log( iv_kind = 'CUA' iv_name = CONV #( iv_prog )
           iv_action = lcl_t=>ui( d = `Fehler` e = `error` )
           iv_text   = |RS_CUA_INTERNAL_WRITE subrc { lv_rc12 } { lv_msg12 }| ).
      RETURN.
    ENDIF.

    log( iv_kind = 'CUA' iv_name = CONV #( iv_prog )
         iv_action = lcl_t=>ui( d = `Oberflaeche gesetzt`
                                e = `GUI status written` )
         iv_text   = |{ lines( lt_sta ) } { lcl_t=>ui( d = `Status` e = `statuses` ) }, | &&
                     |{ lines( lt_fun ) } { lcl_t=>ui( d = `Funktionen` e = `functions` ) }, | &&
                     |{ lines( lt_tit ) } { lcl_t=>ui( d = `Titel` e = `titles` ) }| ).

  ENDMETHOD.

  METHOD put_view.

    DATA ls_dd25v TYPE dd25v.
    DATA ls_dd09v TYPE dd09v.
    DATA lt_dd26v TYPE STANDARD TABLE OF dd26v WITH EMPTY KEY.
    DATA lt_dd27p TYPE STANDARD TABLE OF dd27p WITH EMPTY KEY.
    DATA lt_dd28j TYPE STANDARD TABLE OF dd28j WITH EMPTY KEY.
    DATA lt_dd28v TYPE STANDARD TABLE OF dd28v WITH EMPTY KEY.
    DATA lt_dd35v TYPE STANDARD TABLE OF dd35v WITH EMPTY KEY.
    DATA lt_dd36m TYPE STANDARD TABLE OF dd36m WITH EMPTY KEY.
    DATA ls_dd26v TYPE dd26v.
    DATA ls_dd27p TYPE dd27p.
    DATA ls_dd28j TYPE dd28j.
    DATA ls_dd28v TYPE dd28v.
    DATA ls_dd35v TYPE dd35v.
    DATA ls_dd36m TYPE dd36m.
    DATA lv_obj   TYPE ddobjname.
    DATA lv_rc    TYPE sy-subrc.

    DATA(lv_ex) = exists( iv_kind = 'VIEW' iv_name = iv_name ).
    IF lv_ex = abap_true AND mv_over = abap_false.
      log( iv_kind = 'VIEW' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `uebersprungen` e = `skipped` )
           iv_text   = lcl_t=>ui( d = `existiert bereits` e = `already exists` ) ).
      RETURN.
    ENDIF.

    lcl_attr=>to_struct( EXPORTING it_attrs = io_chapter->get_defhead( )
                         CHANGING  cs_data  = ls_dd25v ).

    LOOP AT io_chapter->get_defrows( ) INTO DATA(ls_row).
      CASE ls_row-tag.
        WHEN 'DD09V'.
          lcl_attr=>to_struct( EXPORTING it_attrs = ls_row-attrs CHANGING cs_data = ls_dd09v ).
        WHEN 'DD26V'.
          CLEAR ls_dd26v.
          lcl_attr=>to_struct( EXPORTING it_attrs = ls_row-attrs CHANGING cs_data = ls_dd26v ).
          APPEND ls_dd26v TO lt_dd26v.
        WHEN 'DD27P'.
          CLEAR ls_dd27p.
          lcl_attr=>to_struct( EXPORTING it_attrs = ls_row-attrs CHANGING cs_data = ls_dd27p ).
          APPEND ls_dd27p TO lt_dd27p.
        WHEN 'DD28J'.
          CLEAR ls_dd28j.
          lcl_attr=>to_struct( EXPORTING it_attrs = ls_row-attrs CHANGING cs_data = ls_dd28j ).
          APPEND ls_dd28j TO lt_dd28j.
        WHEN 'DD28V'.
          CLEAR ls_dd28v.
          lcl_attr=>to_struct( EXPORTING it_attrs = ls_row-attrs CHANGING cs_data = ls_dd28v ).
          APPEND ls_dd28v TO lt_dd28v.
        WHEN 'DD35V'.
          CLEAR ls_dd35v.
          lcl_attr=>to_struct( EXPORTING it_attrs = ls_row-attrs CHANGING cs_data = ls_dd35v ).
          APPEND ls_dd35v TO lt_dd35v.
        WHEN 'DD36M'.
          CLEAR ls_dd36m.
          lcl_attr=>to_struct( EXPORTING it_attrs = ls_row-attrs CHANGING cs_data = ls_dd36m ).
          APPEND ls_dd36m TO lt_dd36m.
      ENDCASE.
    ENDLOOP.

    IF mv_test = abap_true.
      log( iv_kind = 'VIEW' iv_name = iv_name
           iv_action = COND #( WHEN lv_ex = abap_true
                               THEN lcl_t=>ui( d = `wuerde geaendert` e = `would change` )
                               ELSE lcl_t=>ui( d = `wuerde angelegt` e = `would create` ) )
           iv_text   = |{ ls_dd25v-viewclass }, { lines( lt_dd26v ) } | &&
                       |{ lcl_t=>ui( d = `Basistabellen` e = `base tables` ) }, | &&
                       |{ lines( lt_dd27p ) } { lcl_t=>ui( d = `Felder` e = `fields` ) }| ).
      put_maint( io_chapter = io_chapter iv_name = iv_name ).
      RETURN.
    ENDIF.

    lv_obj = iv_name.
    CALL FUNCTION 'DDIF_VIEW_PUT'
      EXPORTING  name              = lv_obj
                 dd25v_wa          = ls_dd25v
                 dd09l_wa          = ls_dd09v
      TABLES     dd26v_tab         = lt_dd26v
                 dd27p_tab         = lt_dd27p
                 dd28j_tab         = lt_dd28j
                 dd28v_tab         = lt_dd28v
                 dd35v_tab         = lt_dd35v
                 dd36m_tab         = lt_dd36m
      EXCEPTIONS view_not_found    = 1
                 name_inconsistent = 2
                 view_inconsistent = 3
                 put_refused       = 4
                 OTHERS            = 5.
    IF sy-subrc <> 0.
      DATA(lv_rc13) = sy-subrc.
      DATA(lv_msg13) = last_message( ).
      log( iv_kind = 'VIEW' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `Fehler` e = `error` )
           iv_text   = |DDIF_VIEW_PUT subrc { lv_rc13 } { lv_msg13 }| ).
      RETURN.
    ENDIF.

    tadir( iv_object = 'VIEW' iv_name = CONV sobj_name( iv_name ) ).

    IF mv_act = abap_true.
      CALL FUNCTION 'DDIF_VIEW_ACTIVATE'
        EXPORTING  name        = lv_obj
                   auth_chk    = abap_true
        IMPORTING  rc          = lv_rc
        EXCEPTIONS not_found   = 1
                   put_failure = 2
                   OTHERS      = 3.
      IF sy-subrc <> 0 OR lv_rc > 4.
        DATA(lv_why_view) = act_reason( iv_kind = 'VIEW' iv_name = iv_name ).
        log( iv_kind = 'VIEW' iv_name = iv_name
             iv_action = lcl_t=>ui( d = `angelegt, inaktiv` e = `created, inactive` )
             iv_text   = |DDIF_VIEW_ACTIVATE rc { lv_rc } { lv_why_view }| ).
        RETURN.
      ENDIF.
    ENDIF.

    put_maint( io_chapter = io_chapter iv_name = iv_name ).

    log( iv_kind = 'VIEW' iv_name = iv_name
         iv_action = COND #( WHEN lv_ex = abap_true
                             THEN lcl_t=>ui( d = `geaendert` e = `changed` )
                             ELSE lcl_t=>ui( d = `angelegt` e = `created` ) )
         iv_text   = |{ lines( lt_dd27p ) } { lcl_t=>ui( d = `Felder` e = `fields` ) }| ).

  ENDMETHOD.

  METHOD put_ddls.

    DATA ls_src TYPE ddddlsrcv.
    DATA lv_ddl TYPE ddlname.

    DATA(lv_ex) = exists( iv_kind = 'DDLS' iv_name = iv_name ).
    IF lv_ex = abap_true AND mv_over = abap_false.
      log( iv_kind = 'DDLS' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `uebersprungen` e = `skipped` )
           iv_text   = lcl_t=>ui( d = `existiert bereits` e = `already exists` ) ).
      RETURN.
    ENDIF.

    DATA(lv_source) = io_chapter->get_defsource( ).
    IF lv_source IS INITIAL.
      log( iv_kind = 'DDLS' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `nicht moeglich` e = `not possible` )
           iv_text   = lcl_t=>ui( d = `keine DDL-Quelle im Dokument`
                                  e = `no DDL source in the document` ) ).
      RETURN.
    ENDIF.

    IF mv_test = abap_true.
      DATA lt_l TYPE STANDARD TABLE OF string WITH EMPTY KEY.
      SPLIT lv_source AT cl_abap_char_utilities=>newline INTO TABLE lt_l.
      log( iv_kind = 'DDLS' iv_name = iv_name
           iv_action = COND #( WHEN lv_ex = abap_true
                               THEN lcl_t=>ui( d = `wuerde geaendert` e = `would change` )
                               ELSE lcl_t=>ui( d = `wuerde angelegt` e = `would create` ) )
           iv_text   = |{ lines( lt_l ) } { lcl_t=>ui( d = `Zeilen` e = `lines` ) }| ).
      RETURN.
    ENDIF.

    lv_ddl = iv_name.
    lcl_attr=>to_struct( EXPORTING it_attrs = io_chapter->get_defhead( )
                         CHANGING  cs_data  = ls_src ).
    CLEAR: ls_src-as4user, ls_src-as4date, ls_src-as4time.
    ls_src-ddlname = lv_ddl.
    ls_src-source  = lv_source.

*   A CDS source has no DDIF_*_PUT. The DDL handler is the only way in,
*   and it works in three steps: save the source, hang the object into
*   the catalogue, activate. Its exceptions are class based.
    TRY.
*       Dynamisch, damit der Report auch ohne CDS-Handler uebersetzt.
        DATA lo_ddl TYPE REF TO object.
        CALL METHOD ('CL_DD_DDL_HANDLER_FACTORY')=>('CREATE')
          RECEIVING handler = lo_ddl.
*       'N' is the new, still inactive version. 'M' is a read state and
*       the handler refuses it here.
        CALL METHOD lo_ddl->('IF_DD_DDL_HANDLER~SAVE')
          EXPORTING name         = lv_ddl
                    put_state    = 'N'
                    ddddlsrcv_wa = ls_src.
      CATCH cx_root INTO DATA(lx_save).
        log( iv_kind = 'DDLS' iv_name = iv_name
             iv_action = lcl_t=>ui( d = `Fehler` e = `error` )
             iv_text   = lx_save->get_text( ) ).
        RETURN.
    ENDTRY.

    TRY.
        CALL METHOD ('CL_DD_DDL_HANDLER')=>('IF_DD_DDL_HANDLER~WRITE_TADIR')
          EXPORTING objectname = lv_ddl
                    devclass   = mv_pack
                    username   = sy-uname
                    prid       = 0.
      CATCH cx_root.
*       The catalogue entry may already be there from an earlier run.
    ENDTRY.

    IF mv_pack NP '$*' AND mv_tr IS NOT INITIAL.
      TRY.
          CALL METHOD lo_ddl->('IF_DD_DDL_HANDLER~WRITE_TRKORR')
            EXPORTING trkorr     = mv_tr
                      objectname = lv_ddl
                      prid       = 0.
        CATCH cx_root.
      ENDTRY.
    ENDIF.

    IF mv_act = abap_true.
      TRY.
          CALL METHOD lo_ddl->('IF_DD_DDL_HANDLER~ACTIVATE')
            EXPORTING name = lv_ddl
                      prid = 0.
        CATCH cx_root INTO DATA(lx_act).
          log( iv_kind = 'DDLS' iv_name = iv_name
               iv_action = lcl_t=>ui( d = `angelegt, inaktiv` e = `created, inactive` )
               iv_text   = lx_act->get_text( ) ).
          RETURN.
      ENDTRY.
    ENDIF.

    log( iv_kind = 'DDLS' iv_name = iv_name
         iv_action = COND #( WHEN lv_ex = abap_true
                             THEN lcl_t=>ui( d = `geaendert` e = `changed` )
                             ELSE lcl_t=>ui( d = `angelegt` e = `created` ) ) ).

  ENDMETHOD.

  METHOD put_clif.

    DATA ls_class TYPE vseoclass.
    DATA ls_intf  TYPE vseointerf.
    DATA lv_corr  TYPE trkorr.
    DATA lt_src   TYPE rswsourcet.
    DATA lv_obj   TYPE trobjtype.

    DATA(lv_ex) = exists( iv_kind = iv_kind iv_name = iv_name ).
    IF lv_ex = abap_true AND mv_over = abap_false.
      log( iv_kind = iv_kind iv_name = iv_name
           iv_action = lcl_t=>ui( d = `uebersprungen` e = `skipped` )
           iv_text   = lcl_t=>ui( d = `existiert bereits` e = `already exists` ) ).
      RETURN.
    ENDIF.

    DATA(lv_source) = io_chapter->get_defsource( ).
    IF lv_source IS INITIAL.
      log( iv_kind = iv_kind iv_name = iv_name
           iv_action = lcl_t=>ui( d = `nicht moeglich` e = `not possible` )
           iv_text   = lcl_t=>ui( d = `kein Quelltext im Dokument`
                                  e = `no source in the document` ) ).
      RETURN.
    ENDIF.
    SPLIT lv_source AT cl_abap_char_utilities=>newline INTO TABLE lt_src.

    IF mv_test = abap_true.
      log( iv_kind = iv_kind iv_name = iv_name
           iv_action = COND #( WHEN lv_ex = abap_true
                               THEN lcl_t=>ui( d = `wuerde geaendert` e = `would change` )
                               ELSE lcl_t=>ui( d = `wuerde angelegt` e = `would create` ) )
           iv_text   = |{ lines( lt_src ) } { lcl_t=>ui( d = `Zeilen` e = `lines` ) }| ).
      RETURN.
    ENDIF.

    IF mv_pack NP '$*'.
      lv_corr = mv_tr.
    ENDIF.

*   Step one: the shell, so that the class exists in the catalogue and
*   belongs to a package. Step two writes the source into it.
    IF iv_kind = 'CLAS'.
      lv_obj = 'CLAS'.
      lcl_attr=>to_struct( EXPORTING it_attrs = io_chapter->get_defhead( )
                           CHANGING  cs_data  = ls_class ).
*     Who wrote it and when belongs to the source system. The UUID too -
*     it identifies this one class, and a copy under another name that
*     carried it would be a second object with the same identity.
      CLEAR: ls_class-author, ls_class-createdon, ls_class-changedby,
             ls_class-changedon, ls_class-chgdanyby, ls_class-chgdanyon,
             ls_class-r3release, ls_class-version, ls_class-uuid.
      ls_class-clsname = iv_name.
      CALL FUNCTION 'SEO_CLASS_CREATE_COMPLETE'
        EXPORTING  devclass        = mv_pack
                   corrnr          = lv_corr
                   overwrite       = abap_true
                   suppress_dialog = abap_true
                   authority_check = abap_true
        CHANGING   class           = ls_class
        EXCEPTIONS existing        = 1
                   is_interface    = 2
                   db_error        = 3
                   component_error = 4
                   no_access       = 5
                   other           = 6
                   OTHERS          = 7.
    ELSE.
      lv_obj = 'INTF'.
      lcl_attr=>to_struct( EXPORTING it_attrs = io_chapter->get_defhead( )
                           CHANGING  cs_data  = ls_intf ).
      CLEAR: ls_intf-author, ls_intf-createdon, ls_intf-changedby,
             ls_intf-changedon, ls_intf-r3release, ls_intf-version,
             ls_intf-uuid.
      ls_intf-clsname = iv_name.
      CALL FUNCTION 'SEO_INTERFACE_CREATE_COMPLETE'
        EXPORTING  devclass        = mv_pack
                   corrnr          = lv_corr
                   overwrite       = abap_true
                   suppress_dialog = abap_true
                   authority_check = abap_true
        CHANGING   interface       = ls_intf
        EXCEPTIONS existing        = 1
                   is_class        = 2
                   db_error        = 3
                   component_error = 4
                   no_access       = 5
                   other           = 6
                   OTHERS          = 7.
    ENDIF.
    IF sy-subrc <> 0.
      DATA(lv_rc14) = sy-subrc.
      DATA(lv_msg14) = last_message( ).
      log( iv_kind = iv_kind iv_name = iv_name
           iv_action = lcl_t=>ui( d = `Fehler` e = `error` )
           iv_text   = |SEO_*_CREATE_COMPLETE subrc { lv_rc14 } { lv_msg14 }| ).
      RETURN.
    ENDIF.

*   Step two: the source-based form, the same text the export read.
    TRY.
        DATA lo_fac  TYPE REF TO object.
        DATA lo_src  TYPE REF TO object.
        DATA lv_clif TYPE seoclsname.
        lv_clif = iv_name.
        CALL METHOD ('CL_OO_FACTORY')=>('CREATE_INSTANCE')
          RECEIVING result = lo_fac.
        CALL METHOD lo_fac->('IF_OO_CLIF_SOURCE_FACTORY~CREATE_CLIF_SOURCE')
          EXPORTING clif_name = lv_clif
          RECEIVING result    = lo_src.
        CALL METHOD lo_src->('IF_OO_CLIF_SOURCE~LOCK')
          EXPORTING authority_check = abap_true.
        CALL METHOD lo_src->('IF_OO_CLIF_SOURCE~SET_SOURCE')
          EXPORTING source = lt_src.
        CALL METHOD lo_src->('IF_OO_CLIF_SOURCE~SAVE').
        CALL METHOD lo_src->('IF_OO_CLIF_SOURCE~UNLOCK').
      CATCH cx_root INTO DATA(lx).
        log( iv_kind = iv_kind iv_name = iv_name
             iv_action = lcl_t=>ui( d = `Fehler` e = `error` )
             iv_text   = lx->get_text( ) ).
        RETURN.
    ENDTRY.

    IF mv_act = abap_true AND activate( iv_object = lv_obj iv_name = iv_name ) = abap_false.
      log( iv_kind = iv_kind iv_name = iv_name
           iv_action = lcl_t=>ui( d = `angelegt, inaktiv` e = `created, inactive` )
           iv_text   = lcl_t=>ui( d = `Aktivierung fehlgeschlagen`
                                  e = `activation failed` ) ).
      RETURN.
    ENDIF.

    log( iv_kind = iv_kind iv_name = iv_name
         iv_action = COND #( WHEN lv_ex = abap_true
                             THEN lcl_t=>ui( d = `geaendert` e = `changed` )
                             ELSE lcl_t=>ui( d = `angelegt` e = `created` ) )
         iv_text   = |{ lines( lt_src ) } { lcl_t=>ui( d = `Zeilen` e = `lines` ) }| ).

  ENDMETHOD.

  METHOD put_fugr.

    DATA lv_area  TYPE rs38l-area.
    DATA lv_corr  TYPE e071-trkorr.
    DATA ls_trdir TYPE trdir.
    DATA lv_incl  TYPE progname.

    DATA(lv_ex) = exists( iv_kind = 'FUGR' iv_name = iv_name ).
    IF lv_ex = abap_true AND mv_over = abap_false.
      log( iv_kind = 'FUGR' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `uebersprungen` e = `skipped` )
           iv_text   = lcl_t=>ui( d = `existiert bereits` e = `already exists` ) ).
      RETURN.
    ENDIF.

    DATA(lt_rows) = io_chapter->get_defrows( ).
    DATA(lv_ninc) = REDUCE i( INIT n = 0 FOR r IN lt_rows
                              NEXT n = COND #( WHEN r-tag = 'INCLUDE' THEN n + 1 ELSE n ) ).
    DATA(lv_nfun) = REDUCE i( INIT n = 0 FOR r IN lt_rows
                              NEXT n = COND #( WHEN r-tag = 'FUNC' THEN n + 1 ELSE n ) ).

    IF mv_test = abap_true.
      log( iv_kind = 'FUGR' iv_name = iv_name
           iv_action = COND #( WHEN lv_ex = abap_true
                               THEN lcl_t=>ui( d = `wuerde geaendert` e = `would change` )
                               ELSE lcl_t=>ui( d = `wuerde angelegt` e = `would create` ) )
           iv_text   = |{ lv_nfun } { lcl_t=>ui( d = `Bausteine` e = `modules` ) }, | &&
                       |{ lv_ninc } Includes| ).
*     Ein Testlauf, der die Bilder verschweigt, macht den Pflegedialog
*     unsichtbar - und genau der ist beim Import das Wackelige.
      put_dynp( io_chapter = io_chapter
                iv_prog    = CONV progname( |SAPL{ iv_name }| ) ).
      RETURN.
    ENDIF.

    IF mv_pack NP '$*'.
      lv_corr = mv_tr.
    ENDIF.
    lv_area = iv_name.

    IF lv_ex = abap_false.
      DATA lv_text TYPE tftit-stext.
      lv_text = lcl_attr=>value( it_attrs = io_chapter->get_defhead( )
                                 iv_name  = 'SHORT_TEXT' ).
      CALL FUNCTION 'RS_FUNCTION_POOL_INSERT'
        EXPORTING  function_pool           = lv_area
                   short_text              = lv_text
                   devclass                = mv_pack
                   corrnum                 = lv_corr
                   suppress_corr_check     = abap_true
                   suppress_language_check = abap_true
                   authority_check         = abap_true
        EXCEPTIONS name_already_exists     = 1
                   name_not_correct        = 2
                   function_already_exists = 3
                   invalid_function_pool   = 4
                   invalid_name            = 5
                   too_many_functions      = 6
                   no_modify_permission    = 7
                   no_show_permission      = 8
                   enqueue_system_failure  = 9
                   canceled_in_corr        = 10
                   undefined_error         = 11
                   OTHERS                  = 12.
      IF sy-subrc <> 0.
        DATA(lv_rc15) = sy-subrc.
        DATA(lv_msg15) = last_message( ).
        log( iv_kind = 'FUGR' iv_name = iv_name
             iv_action = lcl_t=>ui( d = `Fehler` e = `error` )
             iv_text   = |RS_FUNCTION_POOL_INSERT subrc { lv_rc15 } { lv_msg15 }| ).
        RETURN.
      ENDIF.
    ENDIF.

*   The includes first: the TOP include holds the global declarations
*   that the function modules compile against.
    LOOP AT lt_rows INTO DATA(ls_row) WHERE tag = 'INCLUDE'.
      lv_incl = lcl_attr=>value( it_attrs = ls_row-attrs iv_name = 'NAME' ).
      IF lv_incl IS INITIAL OR ls_row-src IS INITIAL.
        CONTINUE.
      ENDIF.
      DATA(lt_code) = to_lines( ls_row-src ).
      CLEAR ls_trdir.
      ls_trdir-name = lv_incl.
      ls_trdir-subc = 'I'.
      ls_trdir-fixpt = abap_true.
      ls_trdir-uccheck = abap_true.
      INSERT REPORT lv_incl FROM lt_code DIRECTORY ENTRY ls_trdir.
      IF sy-subrc <> 0.
        DATA(lv_rc16) = sy-subrc.
        DATA(lv_msg16) = last_message( ).
        log( iv_kind = 'INCL' iv_name = CONV string( lv_incl )
             iv_action = lcl_t=>ui( d = `Fehler` e = `error` )
             iv_text   = |INSERT REPORT subrc { lv_rc16 } { lv_msg16 }| ).
      ENDIF.
    ENDLOOP.

    LOOP AT lt_rows INTO ls_row WHERE tag = 'FUNC'.
      put_func( io_chapter = io_chapter is_row = ls_row iv_area = iv_name ).
    ENDLOOP.

*   Status und Dynpros des Rahmenprogramms - bei einer Pflegegruppe
*   der eigentliche Dialog. Beides vor der Aktivierung, sonst
*   aktiviert der Aufruf eine halbe Gruppe.
    put_cua( io_chapter = io_chapter iv_prog = CONV progname( |SAPL{ iv_name }| ) ).
    put_dynp( io_chapter = io_chapter iv_prog = CONV progname( |SAPL{ iv_name }| ) ).

    IF mv_act = abap_true AND activate( iv_object = 'FUGR' iv_name = iv_name ) = abap_false.
      log( iv_kind = 'FUGR' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `angelegt, inaktiv` e = `created, inactive` )
           iv_text   = lcl_t=>ui( d = `Aktivierung fehlgeschlagen`
                                  e = `activation failed` ) ).
      RETURN.
    ENDIF.

    log( iv_kind = 'FUGR' iv_name = iv_name
         iv_action = COND #( WHEN lv_ex = abap_true
                             THEN lcl_t=>ui( d = `geaendert` e = `changed` )
                             ELSE lcl_t=>ui( d = `angelegt` e = `created` ) )
         iv_text   = |{ lv_nfun } { lcl_t=>ui( d = `Bausteine` e = `modules` ) }, | &&
                     |{ lv_ninc } Includes| ).

  ENDMETHOD.

  METHOD put_func.

    DATA lt_imp TYPE STANDARD TABLE OF rsimp WITH EMPTY KEY.
    DATA lt_cha TYPE STANDARD TABLE OF rscha WITH EMPTY KEY.
    DATA lt_exp TYPE STANDARD TABLE OF rsexp WITH EMPTY KEY.
    DATA lt_tbl TYPE STANDARD TABLE OF rstbl WITH EMPTY KEY.
    DATA lt_exc TYPE STANDARD TABLE OF rsexc WITH EMPTY KEY.
    DATA lt_doc TYPE STANDARD TABLE OF rsfdo WITH EMPTY KEY.
    DATA lt_src TYPE STANDARD TABLE OF rssource WITH EMPTY KEY.
    DATA ls_imp TYPE rsimp.
    DATA ls_cha TYPE rscha.
    DATA ls_exp TYPE rsexp.
    DATA ls_tbl TYPE rstbl.
    DATA ls_exc TYPE rsexc.
    DATA ls_doc TYPE rsfdo.
    DATA lv_corr TYPE e071-trkorr.

    DATA(lv_func) = lcl_attr=>value( it_attrs = is_row-attrs iv_name = 'FUNCNAME' ).
    IF lv_func IS INITIAL.
      RETURN.
    ENDIF.

    SELECT COUNT(*) FROM tfdir WHERE funcname = @lv_func.
    DATA(lv_ex) = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).
    IF lv_ex = abap_true.
      log( iv_kind = 'FUNC' iv_name = lv_func
           iv_action = lcl_t=>ui( d = `uebersprungen` e = `skipped` )
           iv_text   = lcl_t=>ui( d = `existiert bereits` e = `already exists` ) ).
      RETURN.
    ENDIF.

*   Collect the parameter rows that belong to this module.
    LOOP AT io_chapter->get_defrows( ) INTO DATA(ls_p).
      IF lcl_attr=>value( it_attrs = ls_p-attrs iv_name = '_FUNC' ) <> lv_func.
        CONTINUE.
      ENDIF.
      CASE ls_p-tag.
        WHEN 'RSIMP'.
          CLEAR ls_imp.
          lcl_attr=>to_struct( EXPORTING it_attrs = ls_p-attrs CHANGING cs_data = ls_imp ).
          APPEND ls_imp TO lt_imp.
        WHEN 'RSCHA'.
          CLEAR ls_cha.
          lcl_attr=>to_struct( EXPORTING it_attrs = ls_p-attrs CHANGING cs_data = ls_cha ).
          APPEND ls_cha TO lt_cha.
        WHEN 'RSEXP'.
          CLEAR ls_exp.
          lcl_attr=>to_struct( EXPORTING it_attrs = ls_p-attrs CHANGING cs_data = ls_exp ).
          APPEND ls_exp TO lt_exp.
        WHEN 'RSTBL'.
          CLEAR ls_tbl.
          lcl_attr=>to_struct( EXPORTING it_attrs = ls_p-attrs CHANGING cs_data = ls_tbl ).
          APPEND ls_tbl TO lt_tbl.
        WHEN 'RSEXC'.
          CLEAR ls_exc.
          lcl_attr=>to_struct( EXPORTING it_attrs = ls_p-attrs CHANGING cs_data = ls_exc ).
          APPEND ls_exc TO lt_exc.
        WHEN 'RSFDO'.
          CLEAR ls_doc.
          lcl_attr=>to_struct( EXPORTING it_attrs = ls_p-attrs CHANGING cs_data = ls_doc ).
          APPEND ls_doc TO lt_doc.
      ENDCASE.
    ENDLOOP.

    LOOP AT func_body( is_row-src ) INTO DATA(lv_line).
      APPEND VALUE rssource( line = lv_line ) TO lt_src.
    ENDLOOP.

    IF mv_pack NP '$*'.
      lv_corr = mv_tr.
    ENDIF.

    DATA lv_fn   TYPE rs38l-name.
    DATA lv_area TYPE rs38l-area.
    DATA lv_stxt TYPE tftit-stext.
    DATA lv_glob TYPE rs38l-global.
    DATA lv_rem  TYPE rs38l-remote.
    DATA lv_upd  TYPE rs38l-ukind1.
    DATA lv_bas  TYPE rs38l-basxml_enabled.

    lv_fn   = lv_func.
    lv_area = iv_area.
    lv_stxt = lcl_attr=>value( it_attrs = is_row-attrs iv_name = 'SHORT_TEXT' ).
    lv_glob = lcl_attr=>value( it_attrs = is_row-attrs iv_name = 'GLOBAL_FLAG' ).
    lv_rem  = lcl_attr=>value( it_attrs = is_row-attrs iv_name = 'REMOTE_CALL' ).
    lv_upd  = lcl_attr=>value( it_attrs = is_row-attrs iv_name = 'UPDATE_TASK' ).
    lv_bas  = lcl_attr=>value( it_attrs = is_row-attrs iv_name = 'BASXML' ).

    CALL FUNCTION 'RPY_FUNCTIONMODULE_INSERT'
      EXPORTING  funcname                = lv_fn
                 function_pool           = lv_area
                 interface_global        = lv_glob
                 remote_call             = lv_rem
                 short_text              = lv_stxt
                 update_task             = lv_upd
                 remote_basxml_supported = lv_bas
                 corrnum                 = lv_corr
                 suppress_corr_check     = abap_true
      TABLES     import_parameter        = lt_imp
                 export_parameter        = lt_exp
                 tables_parameter        = lt_tbl
                 changing_parameter      = lt_cha
                 exception_list          = lt_exc
                 parameter_docu          = lt_doc
                 source                  = lt_src
      EXCEPTIONS error_message           = 1
                 function_already_exists = 2
                 invalid_function_pool   = 3
                 invalid_name            = 4
                 too_many_functions      = 5
                 no_modify_permission    = 6
                 no_show_permission      = 7
                 enqueue_system_failure  = 8
                 canceled_in_corr        = 9
                 double_task             = 10
                 OTHERS                  = 11.
    IF sy-subrc <> 0.
      DATA(lv_rc17) = sy-subrc.
      DATA(lv_msg17) = last_message( ).
      log( iv_kind = 'FUNC' iv_name = lv_func
           iv_action = lcl_t=>ui( d = `Fehler` e = `error` )
           iv_text   = |RPY_FUNCTIONMODULE_INSERT subrc { lv_rc17 } { lv_msg17 }| ).
      RETURN.
    ENDIF.

    log( iv_kind = 'FUNC' iv_name = lv_func
         iv_action = lcl_t=>ui( d = `angelegt` e = `created` )
         iv_text   = |{ lines( lt_src ) } { lcl_t=>ui( d = `Zeilen` e = `lines` ) }| ).

  ENDMETHOD.

  METHOD put_docu.

    DATA lt_line TYPE STANDARD TABLE OF tline WITH EMPTY KEY.
    DATA ls_head TYPE thead.
    DATA lt_raw  TYPE STANDARD TABLE OF string WITH EMPTY KEY.
    DATA lv_id   TYPE dokhl-id.

    IF mv_test = abap_true.
      RETURN.
    ENDIF.

*   Documentation class per object type - the same key the export read.
    CASE iv_kind.
      WHEN 'PROG'. lv_id = 'RE'.
      WHEN 'DTEL'. lv_id = 'DE'.
      WHEN OTHERS. RETURN.
    ENDCASE.

*   Neuere Dokumente tragen die Dokumentation als DOCU-Zeilen, eine je
*   Sprache. Sie haben Vorrang vor dem Dokumentationstext des Kapitels,
*   der nur mit angehakter Objektdokumentation da ist und nur eine
*   Sprache kennt.
    DATA lv_ndoc TYPE i.
    DATA lv_dlog TYPE string.
    LOOP AT io_chapter->get_defrows( ) INTO DATA(ls_dr) WHERE tag = 'DOCU'.
      DATA(lv_dlang) = lcl_attr=>value( it_attrs = ls_dr-attrs iv_name = 'LANGU' ).
      IF lv_dlang IS INITIAL OR ls_dr-src IS INITIAL.
        CONTINUE.
      ENDIF.
      CLEAR: lt_line, lt_raw, ls_head.
      SPLIT ls_dr-src AT cl_abap_char_utilities=>newline INTO TABLE lt_raw.
      LOOP AT lt_raw INTO DATA(lv_dl).
        DATA ls_dln TYPE tline.
        CLEAR ls_dln.
        SPLIT lv_dl AT cl_abap_char_utilities=>horizontal_tab
              INTO ls_dln-tdformat ls_dln-tdline.
        APPEND ls_dln TO lt_line.
      ENDLOOP.
      ls_head-tdid     = lv_id.
      ls_head-tdspras  = lv_dlang.
      ls_head-tdname   = iv_name.
      ls_head-tdobject = 'DOKU'.
      CALL FUNCTION 'DOCU_UPDATE'
        EXPORTING  head    = ls_head
                   state   = 'A'
                   typ     = 'E'
                   version = 0
        TABLES     line    = lt_line
        EXCEPTIONS OTHERS  = 1.
      IF sy-subrc = 0.
        lv_ndoc = lv_ndoc + 1.
        lv_dlog = |{ lv_dlog } { lv_dlang }|.
      ENDIF.
    ENDLOOP.
    IF lv_ndoc > 0.
      log( iv_kind = 'DOKU' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `Dokumentation gesetzt` e = `documentation written` )
           iv_text   = |{ lcl_t=>ui( d = `Sprachen` e = `languages` ) }{ lv_dlog }| ).
      RETURN.
    ENDIF.

    DATA(lv_text) = io_chapter->get_documentation( ).
    IF lv_text IS INITIAL.
      RETURN.
    ENDIF.

*   The text travels as ITF, one line per row, tag and text separated by
*   a tabulator - the same shape READ_TEXT hands out.
    SPLIT lv_text AT cl_abap_char_utilities=>newline INTO TABLE lt_raw.
    LOOP AT lt_raw INTO DATA(lv_line).
      DATA ls_line TYPE tline.
      CLEAR ls_line.
      SPLIT lv_line AT cl_abap_char_utilities=>horizontal_tab
            INTO ls_line-tdformat ls_line-tdline.
      IF ls_line-tdformat IS INITIAL AND ls_line-tdline IS INITIAL.
        ls_line-tdformat = '/'.
      ENDIF.
      APPEND ls_line TO lt_line.
    ENDLOOP.
    IF lt_line IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lv_lang) = io_chapter->get_doclang( ).
    ls_head-tdid      = lv_id.
    ls_head-tdspras   = COND #( WHEN lv_lang IS NOT INITIAL THEN lv_lang ELSE sy-langu ).
    ls_head-tdname    = iv_name.
    ls_head-tdobject  = 'DOKU'.

    CALL FUNCTION 'DOCU_UPDATE'
      EXPORTING  head    = ls_head
                 state   = 'A'
                 typ     = 'E'
                 version = 0
      TABLES     line    = lt_line
      EXCEPTIONS OTHERS  = 1.
    IF sy-subrc = 0.
      log( iv_kind = 'DOKU' iv_name = iv_name
           iv_action = lcl_t=>ui( d = `Dokumentation gesetzt`
                                  e = `documentation written` ) ).
    ENDIF.

  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* Selection screen
*
* Labels in the source instead of the text pool so that the report stays
* readable when it is copied into another system. The fields of COMMENT
* and FRAME TITLE are created implicitly, their names are limited to
* eight characters.
*----------------------------------------------------------------------*
* Reference fields for the select-options. They do not appear on the
* screen, but SELECT-OPTIONS needs a declared field as a type template.
DATA gv_dummy_typ TYPE tadir-object.
DATA gv_dummy_nam TYPE tadir-obj_name.

* Der zuletzt selbst gebildete Dateinamensvorschlag. Nur solange im
* Feld genau dieser Wert steht, darf der naechste Bildaufbau ihn
* ersetzen - sonst waere ein selbst gewaehlter Name beim naechsten
* Enter wieder weg.
DATA gv_fauto TYPE char128.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE gv_blk1.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tstyp FOR FIELD p_stype.
*   Deliberately not OBLIGATORY. The runtime check runs in the PAI, and
*   it runs on every round trip - including the one that ticks the import
*   flag. The user could then never reach the checkbox without first
*   filling a field the import does not use. The start point is checked
*   in AT SELECTION-SCREEN instead, and only when the run really starts.
    PARAMETERS p_stype TYPE char2 DEFAULT 'K'.
    SELECTION-SCREEN COMMENT 38(40) gv_tstyt.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tsval FOR FIELD p_sval.
    PARAMETERS p_sval TYPE tadir-obj_name.
  SELECTION-SCREEN END OF LINE.
* Der Startpunkt-Typ AL nimmt seine Objekte aus einer Datei. Ein
* Objektname hat dort keinen Platz - eine Pfadangabe passt nicht in
* TADIR-OBJ_NAME, also ein eigenes Feld.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tafil FOR FIELD p_afile.
    PARAMETERS p_afile TYPE char128 LOWER CASE VISIBLE LENGTH 40.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tasrv FOR FIELD p_asrv.
    PARAMETERS p_asrv AS CHECKBOX.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_trec FOR FIELD p_recur.
    PARAMETERS p_recur AS CHECKBOX DEFAULT 'X'.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tloc FOR FIELD p_local.
    PARAMETERS p_local AS CHECKBOX.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE gv_blk2.
  SELECT-OPTIONS s_objtyp FOR gv_dummy_typ.
  SELECT-OPTIONS s_objnam FOR gv_dummy_nam.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tlang FOR FIELD p_langu.
    PARAMETERS p_langu TYPE sy-langu DEFAULT sy-langu.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tfalb FOR FIELD p_falb.
    PARAMETERS p_falb AS CHECKBOX DEFAULT 'X'.
    SELECTION-SCREEN COMMENT 35(14) gv_tflng FOR FIELD p_flang.
    PARAMETERS p_flang TYPE sy-langu DEFAULT 'E'.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tmaxo FOR FIELD p_maxobj.
    PARAMETERS p_maxobj TYPE i DEFAULT 2000.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tdoku FOR FIELD p_doku.
    PARAMETERS p_doku AS CHECKBOX DEFAULT 'X'.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tdet FOR FIELD p_detail.
    PARAMETERS p_detail AS CHECKBOX DEFAULT 'X'.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tsrc FOR FIELD p_src.
    PARAMETERS p_src AS CHECKBOX.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tmaxs FOR FIELD p_maxsrc.
    PARAMETERS p_maxsrc TYPE i DEFAULT 300.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tuse FOR FIELD p_used.
    PARAMETERS p_used AS CHECKBOX.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tcall FOR FIELD p_calls.
    PARAMETERS p_calls AS CHECKBOX.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_trdep FOR FIELD p_rdep.
    PARAMETERS p_rdep TYPE i DEFAULT 1.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tnsap FOR FIELD p_nosap.
    PARAMETERS p_nosap AS CHECKBOX.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tmaxu FOR FIELD p_maxuse.
    PARAMETERS p_maxuse TYPE i DEFAULT 50.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tudep FOR FIELD p_udep.
    PARAMETERS p_udep TYPE i DEFAULT 0.
  SELECTION-SCREEN END OF LINE.
* Ohne dieses Kennzeichen wird der Verwendungsnachweis nur zum
* Startobjekt gezogen. Das ist die richtige Vorgabe: ein Datenelement wie
* CHAR255 haengt an tausenden SAP-Programmen und begruebe das Dokument
* unter seiner eigenen Liste. Wer einen IDoc-Basistyp dokumentiert, will
* aber wissen, wer seine Segmente liest - dafuer der Schalter.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tuall FOR FIELD p_useall.
    PARAMETERS p_useall AS CHECKBOX.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tmaxh FOR FIELD p_maxhit.
    PARAMETERS p_maxhit TYPE i DEFAULT 40.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tfsrc FOR FIELD p_fsrc.
    PARAMETERS p_fsrc AS CHECKBOX.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tdef FOR FIELD p_def.
    PARAMETERS p_def AS CHECKBOX DEFAULT 'X'.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK b2.

SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE gv_blk3.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_txml FOR FIELD p_xml.
    PARAMETERS p_xml AS CHECKBOX.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_thtml FOR FIELD p_html.
    PARAMETERS p_html AS CHECKBOX DEFAULT 'X'.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tfold FOR FIELD p_fold.
    PARAMETERS p_fold TYPE i DEFAULT 100.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_trt FOR FIELD p_rtest.
    PARAMETERS p_rtest AS CHECKBOX DEFAULT 'X'.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(24) gv_tdown FOR FIELD p_down.
    PARAMETERS p_down AS CHECKBOX.
    SELECTION-SCREEN COMMENT 29(18) gv_tpath FOR FIELD p_path.
    PARAMETERS p_path TYPE char128 LOWER CASE DEFAULT 'C:\temp'
                      VISIBLE LENGTH 30.
  SELECTION-SCREEN END OF LINE.
* Der Dateiname ohne Endung - XML und HTML entstehen aus demselben Lauf
* und unterscheiden sich nur darin. Vorbelegt wird er aus Systemkuerzel,
* Startobjekt und Zeitstempel; wer ihn ueberschreibt, behaelt seinen
* Namen. Er gilt fuer den PC-Download und fuer die Serverablage.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(24) gv_tfnam FOR FIELD p_fname.
    PARAMETERS p_fname TYPE char128 LOWER CASE VISIBLE LENGTH 46.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(24) gv_tdsrv FOR FIELD p_dsrv.
    PARAMETERS p_dsrv AS CHECKBOX.
    SELECTION-SCREEN COMMENT 29(18) gv_tsrv FOR FIELD p_srv.
    PARAMETERS p_srv TYPE char128 LOWER CASE VISIBLE LENGTH 30.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK b3.

*----------------------------------------------------------------------*
* Import: the other direction. A document written in system A is read
* here and the objects it defines are created. Nothing is written unless
* the test run is switched off - that is the whole safety net, so it is
* on by default and has to be taken off deliberately.
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b4 WITH FRAME TITLE gv_blk4.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_timp FOR FIELD p_imp.
    PARAMETERS p_imp AS CHECKBOX USER-COMMAND mode.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(24) gv_tifil FOR FIELD p_ifile.
    PARAMETERS p_ifile TYPE char128 LOWER CASE VISIBLE LENGTH 40.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tisrv FOR FIELD p_isrv.
    PARAMETERS p_isrv AS CHECKBOX.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_titst FOR FIELD p_itest.
    PARAMETERS p_itest AS CHECKBOX DEFAULT 'X'.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tiovr FOR FIELD p_iover.
    PARAMETERS p_iover AS CHECKBOX.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tiact FOR FIELD p_iact.
    PARAMETERS p_iact AS CHECKBOX DEFAULT 'X'.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tipck FOR FIELD p_ipack.
    PARAMETERS p_ipack TYPE devclass DEFAULT '$TMP' VISIBLE LENGTH 20.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_titr FOR FIELD p_itr.
    PARAMETERS p_itr TYPE trkorr.
  SELECTION-SCREEN END OF LINE.
* Objekte landen nicht im Auftrag, sondern in einer Aufgabe darunter.
* Gibt es keine offene fuer den Anmeldebenutzer, lehnt das
* Korrektursystem ab - und weil der Import ohne Dialog laeuft, kann es
* nicht danach fragen. Angelegt wird nur unter dem Auftrag, der oben
* steht.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_titsk FOR FIELD p_itask.
    PARAMETERS p_itask AS CHECKBOX DEFAULT 'X'.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tiren FOR FIELD p_iren.
    PARAMETERS p_iren AS CHECKBOX.
  SELECTION-SCREEN END OF LINE.

* Das Zielpaket oben gilt fuer alles. Wer die Paketstruktur des
* Quellsystems behalten oder umlenken will, nimmt die Regeln darunter:
* links das Paket, in dem das Objekt drueben lag, rechts das Paket, in
* dem es hier landen soll. Was keine Regel trifft, geht ins Zielpaket -
* oder, mit "Quellpaket beibehalten", dorthin, wo es herkam.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tikep FOR FIELD p_ikeep.
    PARAMETERS p_ikeep AS CHECKBOX.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(18) gv_tipm1 FOR FIELD p_iold1.
    PARAMETERS p_iold1 TYPE devclass VISIBLE LENGTH 20.
    SELECTION-SCREEN COMMENT 43(4) gv_tiar1.
    PARAMETERS p_inew1 TYPE devclass VISIBLE LENGTH 20.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(18) gv_tipm2 FOR FIELD p_iold2.
    PARAMETERS p_iold2 TYPE devclass VISIBLE LENGTH 20.
    SELECTION-SCREEN COMMENT 43(4) gv_tiar2.
    PARAMETERS p_inew2 TYPE devclass VISIBLE LENGTH 20.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(18) gv_tipm3 FOR FIELD p_iold3.
    PARAMETERS p_iold3 TYPE devclass VISIBLE LENGTH 20.
    SELECTION-SCREEN COMMENT 43(4) gv_tiar3.
    PARAMETERS p_inew3 TYPE devclass VISIBLE LENGTH 20.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(18) gv_tipm4 FOR FIELD p_iold4.
    PARAMETERS p_iold4 TYPE devclass VISIBLE LENGTH 20.
    SELECTION-SCREEN COMMENT 43(4) gv_tiar4.
    PARAMETERS p_inew4 TYPE devclass VISIBLE LENGTH 20.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK b4.

* Traegerbild fuer das editierbare Umbenennungs-Grid. Das Grid selbst
* wird im PBO dieses Bildes ueber einen Docking-Container aufgebaut -
* kein Screen-Painter-Objekt noetig, alles liegt in diesem Report.
SELECTION-SCREEN BEGIN OF SCREEN 2000 TITLE gv_tren2.
  SELECTION-SCREEN COMMENT 1(70) gv_tren3.
SELECTION-SCREEN END OF SCREEN 2000.

INITIALIZATION.
* Screen labels live in the source, not in the text pool, so that a copied
* report is readable in any system. English is the default; German is used
* only when the user is logged on in German.
  IF sy-langu = 'D'.
    gv_blk1  = 'Startpunkt'.
    gv_blk2  = 'Umfang'.
    gv_blk3  = 'Ausgabe'.
    gv_tstyp = 'Typ'.
    gv_tsval = 'Name (Paket, Report, ...)'.
    gv_tafil = 'Fehlliste (nur bei Typ AL)'.
    gv_tasrv = 'Fehlliste liegt auf Appl.-Server'.
    gv_trec  = 'Unterpakete rekursiv (Paket)'.
    gv_tloc  = 'lokale Pakete einbeziehen'.
    gv_tlang = 'Ausgabesprache'.
    gv_tfalb = 'Ersatzsprache verwenden'.
    gv_tflng = 'Ersatzsprache'.
    gv_tmaxo = 'Max. Objekte (0 = alle)'.
    gv_tdoku = 'Objektdokumentation'.
    gv_tdet  = 'Details (Felder, Methoden)'.
    gv_tsrc  = 'Quelltext ausgeben'.
    gv_tmaxs = 'Max. Zeilen je Objekt'.
    gv_tuse  = 'Verwendungsnachweis'.
    gv_tcall = 'Ausgehende Aufrufe'.
    gv_trdep = 'Verweistiefe (0 = keine)'.
    gv_tnsap = 'SAP-Standard ausschliessen'.
    gv_tmaxu = 'Max. Verwendungen je Objekt'.
    gv_tudep = 'Verwendungstiefe (0 = keine)'.
    gv_tuall = 'auch fuer verwendete Objekte'.
    gv_tmaxh = 'Max. Fundstellen je Stelle'.
    gv_tfsrc = 'Fundstellen im ganzen Quelltext'.
    gv_txml  = 'XML erzeugen/ausgeben'.
    gv_thtml = 'HTML erzeugen/anzeigen'.
    gv_tfold = 'HTML einklappen ab Zeilen'.
    gv_trt   = 'Roundtrip prüfen'.
    gv_tdown = 'Download auf PC'.
    gv_tpath = 'Verzeichnis'.
    gv_tfnam = 'Dateiname (ohne Endung)'.
    gv_tdsrv = 'Ablage Appl.-Server'.
    gv_tsrv  = 'Verzeichnis'.
    gv_tdef  = 'Definitionsdaten fuer Reimport'.
    gv_blk4  = 'Import in dieses System'.
    gv_timp  = 'Importieren statt dokumentieren'.
    gv_tifil = 'XML-Datei'.
    gv_tisrv = 'XML-Datei liegt auf Appl.-Server'.
    gv_titst = 'Testlauf (nichts anlegen)'.
    gv_tiovr = 'Bestehende Objekte ueberschreiben'.
    gv_tiact = 'Nach dem Anlegen aktivieren'.
    gv_tipck = 'Zielpaket'.
    gv_titsk = 'Aufgabe anlegen, wenn noetig'.
    gv_tikep = 'Quellpaket beibehalten'.
    gv_tipm1 = 'Paket alt -> neu'.
    gv_tipm2 = 'Paket alt -> neu'.
    gv_tipm3 = 'Paket alt -> neu'.
    gv_tipm4 = 'Paket alt -> neu'.
    gv_tiar1 = '->'.
    gv_tiar2 = '->'.
    gv_tiar3 = '->'.
    gv_tiar4 = '->'.
    gv_titr  = 'Auftrag'.
    gv_tiren = 'Objekte umbenennen'.
    gv_tren2 = 'Objekte umbenennen'.
    gv_tren3 = 'Zielname und Zielpaket bei Bedarf ueberschreiben, dann Ausfuehren.'.
    %_s_objtyp_%_app_%-text = 'Objekttyp'.
    %_s_objnam_%_app_%-text = 'Objektname'.
  ELSE.
    gv_blk1  = 'Start point'.
    gv_blk2  = 'Scope'.
    gv_blk3  = 'Output'.
    gv_tstyp = 'Type'.
    gv_tsval = 'Name (package, report, ...)'.
    gv_tafil = 'Request list (type AL only)'.
    gv_tasrv = 'Request list is on the app server'.
    gv_trec  = 'Include subpackages (package)'.
    gv_tloc  = 'Include local packages'.
    gv_tlang = 'Output language'.
    gv_tfalb = 'Use fallback language'.
    gv_tflng = 'Fallback'.
    gv_tmaxo = 'Max. objects (0 = all)'.
    gv_tdoku = 'Object documentation'.
    gv_tdet  = 'Details (fields, methods)'.
    gv_tsrc  = 'Include source code'.
    gv_tmaxs = 'Max. lines per object'.
    gv_tuse  = 'Where-used list'.
    gv_tcall = 'Outgoing references'.
    gv_trdep = 'Reference depth (0 = none)'.
    gv_tnsap = 'Exclude SAP standard'.
    gv_tmaxu = 'Max. entries per object'.
    gv_tudep = 'Usage depth (0 = none)'.
    gv_tuall = 'also for used objects'.
    gv_tmaxh = 'Max. occurrences per place'.
    gv_tfsrc = 'Occurrences in full source'.
    gv_txml  = 'Create/show XML'.
    gv_thtml = 'Create/show HTML'.
    gv_tfold = 'Collapse HTML from lines'.
    gv_trt   = 'Check roundtrip'.
    gv_tdown = 'Download to PC'.
    gv_tpath = 'Directory'.
    gv_tfnam = 'File name (no extension)'.
    gv_tdsrv = 'Store on app server'.
    gv_tsrv  = 'Directory'.
    gv_tdef  = 'Definition data for reimport'.
    gv_blk4  = 'Import into this system'.
    gv_timp  = 'Import instead of document'.
    gv_tifil = 'XML file'.
    gv_tisrv = 'XML file is on the app server'.
    gv_titst = 'Test run (create nothing)'.
    gv_tiovr = 'Overwrite existing objects'.
    gv_tiact = 'Activate after creation'.
    gv_tipck = 'Target package'.
    gv_titsk = 'Create task if needed'.
    gv_tikep = 'Keep source package'.
    gv_tipm1 = 'Package old -> new'.
    gv_tipm2 = 'Package old -> new'.
    gv_tipm3 = 'Package old -> new'.
    gv_tipm4 = 'Package old -> new'.
    gv_tiar1 = '->'.
    gv_tiar2 = '->'.
    gv_tiar3 = '->'.
    gv_tiar4 = '->'.
    gv_titr  = 'Request'.
    gv_tiren = 'Rename objects'.
    gv_tren2 = 'Rename objects'.
    gv_tren3 = 'Overwrite target name and package as needed, then Execute.'.
* Select-options take their label from the text pool; the COMMENT approach
* used for the other fields does not apply. The generated fields
* %_<name>_%_app_%-text allow setting it at runtime.
    %_s_objtyp_%_app_%-text = 'Object type'.
    %_s_objnam_%_app_%-text = 'Object name'.
  ENDIF.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_path.
  PERFORM f4_verzeichnis.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_stype.
  PERFORM f4_stype.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_sval.
  PERFORM f4_sval.

AT SELECTION-SCREEN OUTPUT.
  IF sy-dynnr = 2000.
    PERFORM ren_pbo.
  ELSE.
* The plain code says little; the text next to it says what was picked.
    PERFORM stype_text USING p_stype CHANGING gv_tstyt.
    PERFORM suggest_fname.
* Die Definitionsdaten fuer den Reimport reisen im XML. Ohne XML-Ausgabe
* stuenden sie in keiner Datei - deshalb wird XML automatisch mit
* aktiviert, sobald "Definitionsdaten fuer Reimport" gesetzt ist.
    IF p_def = abap_true.
      p_xml = abap_true.
    ENDIF.
* On an import run there is no start point. The two fields are declared
* OBLIGATORY for the documentation run; the required flag is taken off
* here so that the screen does not insist on something the run ignores.
    PERFORM screen_mode.
  ENDIF.

AT SELECTION-SCREEN.
  IF sy-dynnr = 2000.
    PERFORM ren_pai.
  ELSE.
* Only when the run really starts. This event also fires on a plain
* round trip - ticking the import flag is one - and checking there would
* block the very box the user is trying to reach.
    IF sy-ucomm = 'ONLI' OR sy-ucomm = 'SJOB' OR sy-ucomm = 'PRIN'.
      IF p_imp = abap_false.
        IF p_stype = 'AL'.
          IF p_afile IS INITIAL.
            MESSAGE lcl_t=>ui( d = `Bitte die Fehlliste angeben.`
                               e = `Please enter the request list.` ) TYPE 'E'.
          ENDIF.
        ELSEIF p_sval IS INITIAL.
          MESSAGE lcl_t=>ui( d = `Bitte einen Startpunkt angeben.`
                             e = `Please enter a start point.` ) TYPE 'E'.
        ENDIF.
        PERFORM check_stype.
      ELSEIF p_ifile IS INITIAL.
        MESSAGE lcl_t=>ui( d = `Bitte die XML-Datei angeben.`
                           e = `Please enter the XML file.` ) TYPE 'E'.
      ENDIF.
    ENDIF.
  ENDIF.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_ifile.
  PERFORM f4_ifile.

*----------------------------------------------------------------------*
* lcl_renderer_html
*----------------------------------------------------------------------*
CLASS lcl_renderer_html DEFINITION.
  PUBLIC SECTION.
    INTERFACES lif_docu_renderer.
*   Blocks longer than this are wrapped in <details>; 0 switches the
*   folding off. Set once from the selection screen.
    CLASS-METHODS set_fold IMPORTING iv_fold TYPE i.
  PRIVATE SECTION.
    CLASS-DATA gv_fold TYPE i.
    DATA mv_html TYPE string.
*   Opens a block: folded away behind a summary line when it is long,
*   otherwise just the note above it. rv_folded has to be handed back to
*   close_block so that the tag is closed exactly when it was opened.
    METHODS open_block
      IMPORTING iv_label         TYPE string
                iv_count         TYPE i
                iv_unit          TYPE string OPTIONAL
      RETURNING VALUE(rv_folded) TYPE abap_bool.
    METHODS close_block IMPORTING iv_folded TYPE abap_bool.
    METHODS add IMPORTING iv_text TYPE string.
    METHODS esc IMPORTING iv_text TYPE string RETURNING VALUE(rv_text) TYPE string.
    METHODS write_chapter IMPORTING io_chapter TYPE REF TO lcl_chapter.
    METHODS write_toc     IMPORTING io_chapter TYPE REF TO lcl_chapter.
    METHODS itf_section
      IMPORTING iv_marker       TYPE string
      RETURNING VALUE(rv_label) TYPE string.
    METHODS itf_to_html
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_html) TYPE string.
ENDCLASS.

CLASS lcl_renderer_html IMPLEMENTATION.

  METHOD add.
    mv_html = |{ mv_html }{ iv_text }{ cl_abap_char_utilities=>newline }|.
  ENDMETHOD.

  METHOD set_fold.
    gv_fold = iv_fold.
  ENDMETHOD.

  METHOD open_block.

    DATA lv_unit TYPE string.

    lv_unit = iv_unit.
    IF lv_unit IS INITIAL.
      lv_unit = lcl_t=>t( d = 'Zeilen' e = 'lines' ).
    ENDIF.

    DATA lv_label TYPE string.

    lv_label = iv_label.
    IF lv_label IS INITIAL.
      lv_label = lcl_t=>t( d = 'Einzelheiten' e = 'Details' ).
    ENDIF.

    IF gv_fold > 0 AND iv_count > gv_fold.
*     <details> is plain HTML - the file stays free of JavaScript, and a
*     browser that does not know the element shows the content anyway.
      rv_folded = abap_true.
      add( |<details><summary>{ esc( lv_label ) } | &&
           |<span class="cnt">({ iv_count } { lv_unit })</span></summary>| ).
    ELSEIF iv_label IS NOT INITIAL.
      add( |<p class="ref">{ esc( iv_label ) }</p>| ).
    ENDIF.

  ENDMETHOD.

  METHOD close_block.
    IF iv_folded = abap_true.
      add( '</details>' ).
    ENDIF.
  ENDMETHOD.

  METHOD esc.
    rv_text = iv_text.
    REPLACE ALL OCCURRENCES OF '&' IN rv_text WITH '&amp;'.
    REPLACE ALL OCCURRENCES OF '<' IN rv_text WITH '&lt;'.
    REPLACE ALL OCCURRENCES OF '>' IN rv_text WITH '&gt;'.
  ENDMETHOD.

  METHOD lif_docu_renderer~render.

    CLEAR mv_html.
    DATA(ls_meta) = io_document->get_meta( ).

    add( '<html><head><meta http-equiv="content-type"' &&
         ' content="text/html; charset=utf-8"><style>' ).
    add( 'body{font-family:Arial,Helvetica,sans-serif;font-size:12px;' &&
         'margin:20px;color:#222}' ).
    add( 'h1{font-size:20px;border-bottom:2px solid #888;padding-bottom:4px}' ).
    add( 'h2{font-size:16px;margin-top:22px}' ).
    add( 'h3,h4,h5,h6{font-size:13px;margin-top:16px}' ).
    add( 'table{border-collapse:collapse;margin:6px 0}' ).
    add( 'th,td{border:1px solid #bbb;padding:3px 7px;text-align:left;' &&
         'font-size:11px}' ).
    add( 'th{background:#eee}' ).
    add( 'div.doc{background:#f7f7f7;border-left:3px solid #bbb;padding:8px;' &&
         'margin:6px 0;line-height:1.45}' ).
    add( 'p.sec{font-weight:bold;margin:10px 0 4px 0;color:#444}' ).
    add( 'div.doc p{margin:0 0 6px 0}' ).
    add( '.ref{color:#666;font-size:11px;margin:2px 0}' ).
    add( '.warn{color:#a00;font-weight:bold}' ).
    add( 'ul.toc{line-height:1.6}' ).
    add( 'pre.src{background:#fbfbf5;border:1px solid #ddd;padding:8px;' &&
         'font-family:Consolas,monospace;font-size:11px;overflow-x:auto;' &&
         'white-space:pre}' ).
    add( 'details{margin:4px 0}' ).
    add( 'summary{color:#666;font-size:11px;cursor:pointer;' &&
         'padding:2px 0;user-select:none}' ).
    add( 'summary:hover{color:#000}' ).
    add( 'span.cnt{color:#999}' ).
    add( '</style></head><body>' ).

*   Die Kopfzeile kommt aus dem Dokument, nicht aus dem Report. Der
*   HTML-Renderer ist in allen drei Reports wortgleich; eine fest
*   verdrahtete Ueberschrift wandert beim Kopieren mit und behauptet
*   dann das Falsche.
    DATA lv_head TYPE string.
    CASE ls_meta-doc_type.
      WHEN 'IMG'.
        lv_head = lcl_t=>t( d = 'Documizer - IMG-Dokumentation'
                            e = 'Documizer - IMG documentation' ).
      WHEN 'DEV'.
        lv_head = lcl_t=>t( d = 'Documizer - Entwicklerdokumentation'
                            e = 'Documizer - developer documentation' ).
      WHEN 'ATC'.
        lv_head = lcl_t=>t( d = 'Documizer - ATC-Pruefkonfiguration'
                            e = 'Documizer - ATC check configuration' ).
      WHEN OTHERS.
        lv_head = 'Documizer'.
    ENDCASE.
    add( |<h1>{ esc( lv_head ) }</h1>| ).

    add( '<table>' ).
    add( |<tr><th>System</th><td>{ esc( ls_meta-system ) }| &&
         | / { lcl_t=>t( d = 'Mandant' e = 'Client' ) } { esc( ls_meta-client ) }</td></tr>| ).
    add( |<tr><th>{ lcl_t=>t( d = 'Erzeugt' e = 'Created' ) }</th>| &&
         |<td>{ esc( ls_meta-created_at ) }| &&
         | { lcl_t=>t( d = 'von' e = 'by' ) } { esc( ls_meta-created_by ) }</td></tr>| ).
    add( |<tr><th>{ lcl_t=>t( d = 'Sprache' e = 'Language' ) }</th>| &&
         |<td>{ esc( ls_meta-language ) }</td></tr>| ).
    add( |<tr><th>{ lcl_t=>t( d = 'Objekte' e = 'Objects' ) }</th>| &&
         |<td>{ ls_meta-node_total } { lcl_t=>t( d = 'gefunden' e = 'found' ) }</td></tr>| ).
    add( '</table>' ).

    IF ls_meta-node_limit > 0 AND ls_meta-node_total > ls_meta-node_limit.
      add( |<p class="warn">{ lcl_t=>t(
             d = |Achtung: Von { ls_meta-node_total } Objekten sind nur | &&
                 |{ ls_meta-node_limit } enthalten. Das Dokument ist | &&
                 |unvollständig.|
             e = |Caution: of { ls_meta-node_total } objects only | &&
                 |{ ls_meta-node_limit } are contained. The document is | &&
                 |incomplete.| ) }</p>| ).
    ENDIF.

    IF ls_meta-src_trunc = abap_true.
      add( |<p class="warn">{ lcl_t=>t(
             d = |Achtung: Mindestens ein Quelltext ist bei | &&
                 |{ ls_meta-src_limit } Zeilen abgeschnitten. Die | &&
                 |Markierung „* ... gekürzt bei" steht im jeweiligen | &&
                 |Quelltext.|
             e = |Caution: at least one source is truncated at | &&
                 |{ ls_meta-src_limit } lines. The marker | &&
                 |"* ... truncated at" is in the source concerned.| ) }</p>| ).
    ENDIF.

    add( |<h2>{ lcl_t=>t( d = 'Inhalt' e = 'Contents' ) }</h2><ul class="toc">| ).
    LOOP AT io_document->get_chapters( ) INTO DATA(lo_top).
      write_toc( lo_top ).
    ENDLOOP.
    add( '</ul>' ).

    LOOP AT io_document->get_chapters( ) INTO DATA(lo_chapter).
      write_chapter( lo_chapter ).
    ENDLOOP.

    add( '</body></html>' ).

    rv_content = mv_html.

  ENDMETHOD.

  METHOD itf_section.
*   Object documentation is divided into fixed sections that appear in the
*   ITF text as &NAME&. They become subheadings; the raw markers said
*   nothing to the reader.
    CASE iv_marker.
      WHEN 'DEFINITION'.     rv_label = lcl_t=>t( d = 'Definition' e = 'Definition' ).
      WHEN 'DESCRIPTION'.    rv_label = lcl_t=>t( d = 'Beschreibung' e = 'Description' ).
      WHEN 'SHORTTEXT'.      rv_label = lcl_t=>t( d = 'Kurztext' e = 'Short text' ).
      WHEN 'USE'.            rv_label = lcl_t=>t( d = 'Verwendung' e = 'Use' ).
      WHEN 'DEPENDENCIES'.   rv_label = lcl_t=>t( d = 'Abhängigkeiten' e = 'Dependencies' ).
      WHEN 'PRECONDITIONS'.  rv_label = lcl_t=>t( d = 'Voraussetzungen' e = 'Prerequisites' ).
      WHEN 'STANDARD_SETUP'. rv_label = lcl_t=>t( d = 'Standardeinstellungen' e = 'Standard settings' ).
      WHEN 'ACTIVITY'.       rv_label = lcl_t=>t( d = 'Vorgehen' e = 'Activities' ).
      WHEN 'EXAMPLE'.        rv_label = lcl_t=>t( d = 'Beispiel' e = 'Example' ).
      WHEN 'RECOMMENDATION'. rv_label = lcl_t=>t( d = 'Empfehlung' e = 'Recommendation' ).
      WHEN 'CAUTION'.        rv_label = lcl_t=>t( d = 'Achtung' e = 'Caution' ).
      WHEN 'FUNCTIONALITY'.  rv_label = lcl_t=>t( d = 'Funktionsumfang' e = 'Functionality' ).
      WHEN 'PARAMETERS'.     rv_label = lcl_t=>t( d = 'Parameter' e = 'Parameters' ).
      WHEN 'HINTS'.          rv_label = lcl_t=>t( d = 'Hinweise' e = 'Notes' ).
      WHEN OTHERS.           rv_label = iv_marker.
    ENDCASE.
  ENDMETHOD.

  METHOD itf_to_html.
*   The documentation arrives as ITF. Section markers become headings,
*   the markup becomes bold - the same conversion the IMG report does, so
*   both documents read alike.
    DATA lt_lines TYPE STANDARD TABLE OF string.
    DATA lv_line  TYPE string.
    DATA lv_len   TYPE i.

    SPLIT iv_text AT cl_abap_char_utilities=>newline INTO TABLE lt_lines.

    rv_html = '<div class="doc">'.

    LOOP AT lt_lines INTO lv_line.

      CONDENSE lv_line.

*     SAPscript control statement, no content
      IF lv_line = 'RESET N1'.
        CONTINUE.
      ENDIF.

      IF lv_line IS INITIAL.
        rv_html = |{ rv_html }<p></p>|.
        CONTINUE.
      ENDIF.

*     A marker may sit alone on its line or lead the text that follows.
      lv_len = strlen( lv_line ).
      FIND REGEX '^&[A-Z0-9_]+&$' IN lv_line ##REGEX_POSIX.
      IF sy-subrc = 0.
        rv_html = |{ rv_html }<p class="sec">{ esc(
                    itf_section( substring( val = lv_line off = 1 len = lv_len - 2 ) ) ) }</p>|.
        CONTINUE.
      ENDIF.

      DATA lv_mark TYPE string.
      FIND FIRST OCCURRENCE OF REGEX '^&([A-Z0-9_]+)&\s*' IN lv_line
           SUBMATCHES lv_mark ##REGEX_POSIX.
      IF sy-subrc = 0.
        REPLACE FIRST OCCURRENCE OF REGEX '^&[A-Z0-9_]+&\s*' IN lv_line WITH '' ##REGEX_POSIX.
        rv_html = |{ rv_html }<p class="sec">{ esc( itf_section( lv_mark ) ) }</p>|.
        IF lv_line IS INITIAL.
          CONTINUE.
        ENDIF.
      ENDIF.

      lv_line = esc( lv_line ).

*     ITF markup. All two- to three-character markers are handled
*     generically, cross references <DS:...> come along; the closing
*     marker </> applies to every one of them.
      REPLACE ALL OCCURRENCES OF REGEX '&lt;DS:[^&]+&gt;' IN lv_line WITH '<b>' ##REGEX_POSIX.
      REPLACE ALL OCCURRENCES OF '&lt;/&gt;' IN lv_line WITH '</b>'.
      REPLACE ALL OCCURRENCES OF REGEX '&lt;[A-Z0-9]{2,3}&gt;' IN lv_line WITH '<b>' ##REGEX_POSIX.

*     Balance per line, otherwise an open marker styles the rest of the
*     document.
      DATA(lv_open)  = count( val = lv_line sub = '<b>' ).
      DATA(lv_close) = count( val = lv_line sub = '</b>' ).
      IF lv_open > lv_close.
        DO lv_open - lv_close TIMES.
          lv_line = |{ lv_line }</b>|.
        ENDDO.
      ELSEIF lv_close > lv_open.
        DO lv_close - lv_open TIMES.
          REPLACE FIRST OCCURRENCE OF '</b>' IN lv_line WITH ''.
        ENDDO.
      ENDIF.

*     Tabs of the ITF storage format
      REPLACE ALL OCCURRENCES OF ',,' IN lv_line WITH ' '.

      rv_html = |{ rv_html }{ lv_line }<br>|.

    ENDLOOP.

    rv_html = |{ rv_html }</div>|.

  ENDMETHOD.

  METHOD write_toc.
    IF io_chapter->get_level( ) > 2.
      RETURN.
    ENDIF.
    add( |<li><a href="#c{ esc( io_chapter->get_id( ) ) }">| &&
         |{ esc( io_chapter->get_id( ) ) } { esc( io_chapter->get_title( ) ) }</a></li>| ).
    LOOP AT io_chapter->get_children( ) INTO DATA(lo_child).
      write_toc( lo_child ).
    ENDLOOP.
  ENDMETHOD.

  METHOD write_chapter.

    DATA lv_h TYPE i.

    lv_h = io_chapter->get_level( ).
    IF lv_h > 6.
      lv_h = 6.
    ENDIF.
    IF lv_h < 2.
      lv_h = 2.
    ENDIF.

    add( |<h{ lv_h } id="c{ esc( io_chapter->get_id( ) ) }">| &&
         |{ esc( io_chapter->get_id( ) ) } { esc( io_chapter->get_title( ) ) }</h{ lv_h }>| ).

    IF io_chapter->has_reference( ) = abap_true.
      DATA(ls_ref) = io_chapter->get_reference( ).
      add( |<p class="ref">{ lcl_t=>t( d = 'Typ' e = 'Type' ) }| &&
           | { esc( ls_ref-activity ) }| &&
           | &nbsp; { lcl_t=>t( d = 'Paket' e = 'package' ) } { esc( ls_ref-tcode ) }| &&
           | &nbsp; { lcl_t=>t( d = 'Autor' e = 'author' ) } { esc( ls_ref-docu_id ) }</p>| ).
    ENDIF.

    IF io_chapter->get_documentation( ) IS NOT INITIAL.
      add( itf_to_html( io_chapter->get_documentation( ) ) ).
    ENDIF.

    IF io_chapter->get_source( ) IS NOT INITIAL.
      DATA(lv_src) = io_chapter->get_source( ).
      DATA(lv_fold) = open_block(
        iv_label = lcl_t=>t( d = 'Quelltext' e = 'Source code' )
        iv_count = count( val = lv_src sub = cl_abap_char_utilities=>newline ) + 1 ).
      add( |<pre class="src">{ esc( lv_src ) }</pre>| ).
      close_block( lv_fold ).
    ENDIF.

    LOOP AT io_chapter->get_objects( ) INTO DATA(lo_obj).
      DATA(lv_cnt) = lines( lo_obj->get_fields( ) ).

*     Source hits belong in a code block, not in a field table: the line
*     number in front, the statement behind it, in a fixed-width font.
      IF lo_obj->get_type( ) = 'SOURCE'.
        lv_fold = open_block( iv_label = lo_obj->get_note( ) iv_count = lv_cnt ).
        add( '<pre class="src">' ).
        LOOP AT lo_obj->get_fields( ) INTO DATA(ls_hit).
          IF ls_hit-keyflag = abap_true.
            add( |<b>{ esc( ls_hit-name ) }  { esc( ls_hit-rollname ) }</b>| ).
          ELSE.
            add( |{ esc( ls_hit-name ) }  { esc( ls_hit-rollname ) }| ).
          ENDIF.
        ENDLOOP.
        add( '</pre>' ).
        close_block( lv_fold ).
        CONTINUE.
      ENDIF.

      IF lv_cnt > 0.
        lv_fold = open_block( iv_label = lo_obj->get_note( )
                              iv_count = lv_cnt
                              iv_unit  = lcl_t=>t( d = 'Einträge' e = 'entries' ) ).
        add( |<table><tr><th>Name</th>| &&
             |<th>{ lcl_t=>t( d = 'Typ / Datenelement'
                              e = 'Type / data element' ) }</th>| &&
             |<th>{ lcl_t=>t( d = 'Schlüssel' e = 'Key' ) }</th></tr>| ).
        LOOP AT lo_obj->get_fields( ) INTO DATA(ls_fs).
          add( |<tr><td>{ esc( ls_fs-name ) }</td>| &&
               |<td>{ esc( ls_fs-rollname ) }</td>| &&
               |<td>{ COND string( WHEN ls_fs-keyflag = abap_true THEN 'X' ELSE '' ) }</td></tr>| ).
        ENDLOOP.
        add( '</table>' ).
        close_block( lv_fold ).
      ELSEIF lo_obj->get_note( ) IS NOT INITIAL.
        add( |<p class="ref">{ esc( lo_obj->get_note( ) ) }</p>| ).
      ENDIF.
    ENDLOOP.

    LOOP AT io_chapter->get_children( ) INTO DATA(lo_child).
      write_chapter( lo_child ).
    ENDLOOP.

  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* lcl_collector_dev
*----------------------------------------------------------------------*
CLASS lcl_collector_dev DEFINITION.
  PUBLIC SECTION.
    INTERFACES lif_docu_collector.
    METHODS constructor
      IMPORTING iv_stype  TYPE char2
                iv_sval   TYPE string
                iv_rdep   TYPE i
                iv_recur  TYPE abap_bool
                iv_local  TYPE abap_bool
                iv_langu  TYPE sy-langu
                iv_maxobj TYPE i
                iv_doku   TYPE abap_bool
                iv_detail TYPE abap_bool
                iv_src    TYPE abap_bool
                iv_maxsrc TYPE i
                iv_used   TYPE abap_bool
                iv_useall TYPE abap_bool DEFAULT abap_false
                iv_maxuse TYPE i
                iv_falb   TYPE abap_bool
                iv_flang  TYPE sy-langu
                iv_calls  TYPE abap_bool
                iv_nosap  TYPE abap_bool
                iv_maxhit TYPE i
                iv_fsrc   TYPE abap_bool
                iv_udep   TYPE i
                iv_def    TYPE abap_bool
*               Mehrere Startobjekte statt eines: die Fehlliste aus dem
*               Zielsystem. Ist die Tabelle gefuellt, tritt sie an die
*               Stelle von iv_stype/iv_sval.
                it_start  TYPE ty_objrefs OPTIONAL.
    METHODS get_stat_packages RETURNING VALUE(rv) TYPE i.
    METHODS get_stat_objects  RETURNING VALUE(rv) TYPE i.
    METHODS get_stat_total    RETURNING VALUE(rv) TYPE i.
    METHODS get_stat_docu     RETURNING VALUE(rv) TYPE i.
    METHODS get_stat_source   RETURNING VALUE(rv) TYPE i.
    METHODS get_stat_usage    RETURNING VALUE(rv) TYPE i.
    METHODS get_stat_fallback RETURNING VALUE(rv) TYPE i.
    METHODS get_stat_calls    RETURNING VALUE(rv) TYPE i.
    METHODS get_stat_def      RETURNING VALUE(rv) TYPE i.
  PRIVATE SECTION.
    DATA mv_stype  TYPE char2.
    DATA mv_sval   TYPE string.
    DATA mv_rdep   TYPE i.
    DATA mv_pack   TYPE devclass.
    DATA mv_recur  TYPE abap_bool.
    DATA mv_local  TYPE abap_bool.
    DATA mv_langu  TYPE sy-langu.
    DATA mv_maxobj TYPE i.
    DATA mv_doku   TYPE abap_bool.
    DATA mv_detail TYPE abap_bool.
    DATA mv_src    TYPE abap_bool.
    DATA mv_maxsrc TYPE i.
    DATA mv_used   TYPE abap_bool.
*   Verwendungsnachweis auch zu den verwendeten Objekten, nicht nur zum
*   Startobjekt.
    DATA mv_useall TYPE abap_bool.
    DATA mv_maxuse TYPE i.
    DATA mv_calls  TYPE abap_bool.
    DATA mv_nosap  TYPE abap_bool.
    DATA mv_maxhit TYPE i.
    DATA mv_udep   TYPE i.
    DATA mv_fsrc   TYPE abap_bool.
    DATA mv_falb   TYPE abap_bool.
    DATA mv_flang  TYPE sy-langu.
    DATA mv_n_falb TYPE i.
    DATA mv_last_lang TYPE sy-langu.
    DATA mv_note   TYPE string.
    DATA mv_n_use  TYPE i.
    DATA mv_n_call TYPE i.
    DATA mv_n_src  TYPE i.
    DATA mv_src_trunc TYPE abap_bool.
    DATA mv_n_pack TYPE i.
    DATA mv_n_obj  TYPE i.
    DATA mv_n_tot  TYPE i.
    DATA mv_n_docu TYPE i.
    DATA mv_def    TYPE abap_bool.
    DATA mv_n_def  TYPE i.
    DATA mt_start  TYPE ty_objrefs.

*   Definition data for the reimport. One method per object type, all of
*   them reading exactly the structures that the matching DDIF_*_PUT
*   expects - what is written here can be handed back unchanged.
    METHODS add_definition
      IMPORTING iv_type    TYPE trobjtype
                iv_name    TYPE sobj_name
                io_chapter TYPE REF TO lcl_chapter.
    METHODS def_doma
      IMPORTING iv_name    TYPE sobj_name
                io_chapter TYPE REF TO lcl_chapter
      RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS def_dtel
      IMPORTING iv_name    TYPE sobj_name
                io_chapter TYPE REF TO lcl_chapter
      RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS def_tabl
      IMPORTING iv_name    TYPE sobj_name
                io_chapter TYPE REF TO lcl_chapter
      RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS def_prog
      IMPORTING iv_name    TYPE sobj_name
                io_chapter TYPE REF TO lcl_chapter
      RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS def_cua
      IMPORTING io_chapter TYPE REF TO lcl_chapter
                iv_prog    TYPE progname.
    METHODS def_dynp
      IMPORTING io_chapter TYPE REF TO lcl_chapter
                iv_prog    TYPE progname.
    METHODS def_docu
      IMPORTING iv_kind    TYPE trobjtype
                iv_name    TYPE sobj_name
                io_chapter TYPE REF TO lcl_chapter.
    METHODS def_tran
      IMPORTING iv_name      TYPE sobj_name
                io_chapter   TYPE REF TO lcl_chapter
      RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS def_vcls
      IMPORTING iv_name      TYPE sobj_name
                io_chapter   TYPE REF TO lcl_chapter
      RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS def_maint
      IMPORTING iv_name    TYPE sobj_name
                io_chapter TYPE REF TO lcl_chapter.
*   BDEF, SRVD und DDLX sind quelltextbasiert und haengen alle am
*   generischen Workbench-Objektoperator - ein Weg statt drei.
    METHODS def_wbsrc
      IMPORTING iv_type      TYPE trobjtype
                iv_name      TYPE sobj_name
                io_chapter   TYPE REF TO lcl_chapter
      RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS def_srvb
      IMPORTING iv_name      TYPE sobj_name
                io_chapter   TYPE REF TO lcl_chapter
      RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS def_segm
      IMPORTING iv_name      TYPE sobj_name
                io_chapter   TYPE REF TO lcl_chapter
      RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS def_idoc
      IMPORTING iv_name      TYPE sobj_name
                io_chapter   TYPE REF TO lcl_chapter
      RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS def_wapa
      IMPORTING iv_name      TYPE sobj_name
                io_chapter   TYPE REF TO lcl_chapter
      RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS def_msag
      IMPORTING iv_name    TYPE sobj_name
                io_chapter TYPE REF TO lcl_chapter
      RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS def_view
      IMPORTING iv_name    TYPE sobj_name
                io_chapter TYPE REF TO lcl_chapter
      RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS def_ddls
      IMPORTING iv_name    TYPE sobj_name
                io_chapter TYPE REF TO lcl_chapter
      RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS def_clif
      IMPORTING iv_type    TYPE trobjtype
                iv_name    TYPE sobj_name
                io_chapter TYPE REF TO lcl_chapter
      RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS def_fugr
      IMPORTING iv_name    TYPE sobj_name
                io_chapter TYPE REF TO lcl_chapter
      RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS def_func
      IMPORTING iv_func    TYPE rs38l_fnam
                io_chapter TYPE REF TO lcl_chapter.
*   Reimport-Definitionsdaten einer Adobe-Form-Schnittstelle (SFPI):
*   Parameter, globale Definitionen und Coding aus dem Objektmodell.
    METHODS def_sfpi
      IMPORTING iv_name      TYPE sobj_name
                io_chapter   TYPE REF TO lcl_chapter
      RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS def_sfp_code_row
      IMPORTING iv_tag     TYPE string
                it_code    TYPE tfpcoding
                io_chapter TYPE REF TO lcl_chapter.
*   Reimport-Definitionsdaten eines Adobe-Formulars (SFPF): Kopfdaten
*   im Klartext, Kontext und Layout als SAP-eigene Serialisierung.
    METHODS def_sfpf
      IMPORTING iv_name      TYPE sobj_name
                io_chapter   TYPE REF TO lcl_chapter
      RETURNING VALUE(rv_ok) TYPE abap_bool.
*   The complete source of a class or interface in its source-based
*   form - the text SE24 and ADT show, not the generated includes.
    METHODS clif_source
      IMPORTING iv_name          TYPE sobj_name
      RETURNING VALUE(rv_source) TYPE string.
    METHODS report_source
      IMPORTING iv_prog          TYPE progname
      RETURNING VALUE(rv_source) TYPE string.

    METHODS read_short_text
      IMPORTING iv_type        TYPE trobjtype
                iv_name        TYPE sobj_name
      RETURNING VALUE(rv_text) TYPE string.
    METHODS read_text_lang
      IMPORTING iv_type        TYPE trobjtype
                iv_name        TYPE sobj_name
                iv_langu       TYPE sy-langu
      RETURNING VALUE(rv_text) TYPE string.
    METHODS read_docu
      IMPORTING iv_type        TYPE trobjtype
                iv_name        TYPE sobj_name
      RETURNING VALUE(rv_text) TYPE string.
    METHODS read_docu_lang
      IMPORTING iv_type        TYPE trobjtype
                iv_name        TYPE sobj_name
                iv_langu       TYPE sy-langu
      RETURNING VALUE(rv_text) TYPE string.
    METHODS add_details
      IMPORTING iv_type    TYPE trobjtype
                iv_name    TYPE sobj_name
                io_chapter TYPE REF TO lcl_chapter.
    METHODS type_title
      IMPORTING iv_type         TYPE trobjtype
      RETURNING VALUE(rv_title) TYPE string.
    METHODS build_title
      IMPORTING iv_name         TYPE string
                iv_text         TYPE string
      RETURNING VALUE(rv_title) TYPE string.
    METHODS read_source
      IMPORTING iv_type          TYPE trobjtype
                iv_name          TYPE sobj_name
      RETURNING VALUE(rv_source) TYPE string.
    METHODS source_lines
      IMPORTING iv_type          TYPE trobjtype
                iv_name          TYPE sobj_name
      RETURNING VALUE(rt_source) TYPE string_table.
*   Smart Form (SSFO): Baum, Schnittstelle, globale Definitionen und das
*   Coding der Code-Knoten. Nichts davon steht in einer lesbaren
*   DDIC-Tabelle - die Struktur liegt allein im Objektmodell des Form
*   Builders vor und wird ueber CL_SSF_FB_SMART_FORM geladen.
    METHODS ssfo_form
      IMPORTING iv_name        TYPE sobj_name
      RETURNING VALUE(ro_form) TYPE REF TO cl_ssf_fb_smart_form.
    METHODS ssfo_type_label
      IMPORTING iv_type         TYPE clike
      RETURNING VALUE(rv_label) TYPE string.
    METHODS ssfo_tree
      IMPORTING io_node    TYPE REF TO cl_ssf_fb_node
                iv_outline TYPE string
      CHANGING  ct_field   TYPE ty_fields.
    METHODS ssfo_code
      IMPORTING io_node TYPE REF TO cl_ssf_fb_node
      CHANGING  ct_src  TYPE string_table.
*   Adobe Form (SFPF) und Adobe-Form-Schnittstelle (SFPI): Schnittstelle,
*   globale Definitionen, Coding und - beim Formular - der Kontextbaum.
*   Nichts davon steht in einer lesbaren DDIC-Tabelle; die Struktur liegt
*   als XML in der Ablage und wird ueber das Objektmodell der Form-
*   Workbench (CL_FP_WB_FORM / CL_FP_WB_INTERFACE) geladen.
    METHODS sfpf_form
      IMPORTING iv_name        TYPE sobj_name
      RETURNING VALUE(ro_form) TYPE REF TO if_fp_form.
    METHODS sfpi_ifc_data
      IMPORTING iv_name        TYPE sobj_name
      RETURNING VALUE(ro_data) TYPE REF TO if_fp_interface_data.
    METHODS sfpi_source
      IMPORTING iv_name          TYPE sobj_name
      RETURNING VALUE(rt_source) TYPE string_table.
    METHODS sfp_trim_code
      IMPORTING it_code         TYPE tfpcoding
      RETURNING VALUE(rt_lines) TYPE string_table.
    METHODS sfpf_node_label
      IMPORTING iv_type         TYPE i
      RETURNING VALUE(rv_label) TYPE string.
    METHODS sfpf_context
      IMPORTING io_node    TYPE REF TO if_fp_node
                iv_outline TYPE string
      CHANGING  ct_field   TYPE ty_fields.
    METHODS sfp_param_rows
      IMPORTING io_obj TYPE REF TO lcl_object
                it_par TYPE tfpiopar
                iv_dir TYPE c.
    METHODS add_sfp_ifc_blocks
      IMPORTING iv_type    TYPE trobjtype
                iv_name    TYPE sobj_name
                iv_ifname  TYPE sobj_name
                io_chapter TYPE REF TO lcl_chapter.
    METHODS append_report
      IMPORTING iv_prog   TYPE syrepid
      CHANGING  ct_source TYPE string_table.
    METHODS add_usages
      IMPORTING iv_type    TYPE trobjtype
                iv_name    TYPE sobj_name
                io_chapter TYPE REF TO lcl_chapter.
    METHODS main_program
      IMPORTING iv_include     TYPE progname
      RETURNING VALUE(rv_prog) TYPE progname.
    METHODS prog_kind
      IMPORTING iv_subc        TYPE trdir-subc
                iv_prog        TYPE progname
      RETURNING VALUE(rv_kind) TYPE string.
    METHODS find_obj_cls
      IMPORTING iv_type       TYPE trobjtype
      RETURNING VALUE(rv_cls) TYPE euobj-id.
    METHODS crossref_users
      IMPORTING iv_type       TYPE trobjtype
                iv_name       TYPE sobj_name
                iv_with_encl  TYPE abap_bool DEFAULT abap_false
      EXPORTING et_hit        TYPE ty_objrefs
                ev_ok         TYPE abap_bool.
    METHODS usage_objects
      IMPORTING iv_type       TYPE trobjtype
                iv_name       TYPE sobj_name
      RETURNING VALUE(rt_obj) TYPE ty_objrefs.
    METHODS usage_scan
      IMPORTING iv_prog   TYPE progname
                iv_name   TYPE sobj_name
                iv_access TYPE abap_bool
      EXPORTING ev_access TYPE string
                et_hits   TYPE ty_hits.
    METHODS add_calls
      IMPORTING iv_type    TYPE trobjtype
                iv_name    TYPE sobj_name
                io_chapter TYPE REF TO lcl_chapter.
    METHODS pack_reason
      IMPORTING iv_subrc         TYPE sy-subrc
      RETURNING VALUE(rv_reason) TYPE string.

*   Single-object entry point and reference expansion
    METHODS func_include
      IMPORTING iv_func           TYPE rs38l_fnam
      RETURNING VALUE(rv_include) TYPE syrepid.
    METHODS func_group
      IMPORTING iv_func         TYPE rs38l_fnam
      RETURNING VALUE(rv_group) TYPE rs38l_area.
    METHODS cross_prefix
      IMPORTING iv_type          TYPE trobjtype
                iv_name          TYPE sobj_name
      RETURNING VALUE(rv_prefix) TYPE string.
    METHODS start_object
      RETURNING VALUE(rs_obj) TYPE ty_objref.
    METHODS collect_refs
      IMPORTING iv_type       TYPE trobjtype
                iv_name       TYPE sobj_name
      RETURNING VALUE(rt_ref) TYPE ty_objrefs.
    METHODS scan_source_calls
      IMPORTING iv_type       TYPE trobjtype
                iv_name       TYPE sobj_name
      RETURNING VALUE(rt_ref) TYPE ty_objrefs.
    METHODS base_name
      IMPORTING iv_name        TYPE string
      RETURNING VALUE(rv_base) TYPE sobj_name.
    METHODS own_names
      IMPORTING it_name       TYPE ty_names
      RETURNING VALUE(rt_own) TYPE ty_names.
    METHODS drop_sap
      CHANGING ct_ref TYPE ty_objrefs.
    METHODS resolve_repo_object
      IMPORTING iv_name       TYPE string
      RETURNING VALUE(rs_ref) TYPE ty_objref.
    METHODS document_object
      IMPORTING iv_type           TYPE trobjtype
                iv_name           TYPE sobj_name
                iv_id             TYPE string
                iv_level          TYPE i
                iv_calls          TYPE abap_bool DEFAULT abap_false
                iv_root           TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(ro_chapter) TYPE REF TO lcl_chapter.
    METHODS collect_single
      CHANGING co_document TYPE REF TO lcl_document
               cv_trunc    TYPE abap_bool.
ENDCLASS.

CLASS lcl_collector_dev IMPLEMENTATION.

  METHOD constructor.
    mv_stype  = iv_stype.
    mv_sval   = to_upper( condense( iv_sval ) ).
    mv_rdep   = iv_rdep.
    mv_pack   = mv_sval.
    mv_recur  = iv_recur.
    mv_local  = iv_local.
    mv_langu  = iv_langu.
    mv_maxobj = iv_maxobj.
    mv_doku   = iv_doku.
    mv_detail = iv_detail.
    mv_src    = iv_src.
    mv_maxsrc = iv_maxsrc.
    mv_used   = iv_used.
    mv_useall = iv_useall.
    mv_calls  = iv_calls.
    mv_nosap  = iv_nosap.
    mv_maxhit = iv_maxhit.
    mv_fsrc   = iv_fsrc.
    mv_udep   = iv_udep.
    mv_maxuse = iv_maxuse.
    mv_falb   = iv_falb.
    mv_flang  = iv_flang.
    mv_def    = iv_def.
    mt_start  = it_start.
  ENDMETHOD.

  METHOD build_title.
    " Without a short text a dangling dash would be left at the end.
    DATA lv_text TYPE string.
    lv_text = iv_text.
    CONDENSE lv_text.
    IF lv_text IS INITIAL.
      rv_title = iv_name.
    ELSE.
      rv_title = |{ iv_name } - { lv_text }|.
    ENDIF.
  ENDMETHOD.

  METHOD type_title.
    CASE iv_type.
      WHEN 'PROG'. rv_title = lcl_t=>t( d = 'Programme' e = 'Programs' ).
      WHEN 'CLAS'. rv_title = lcl_t=>t( d = 'Klassen' e = 'Classes' ).
      WHEN 'INTF'. rv_title = 'Interfaces'.
      WHEN 'FUGR'. rv_title = lcl_t=>t( d = 'Funktionsgruppen' e = 'Function groups' ).
      WHEN 'TABL'. rv_title = lcl_t=>t( d = 'Tabellen und Strukturen' e = 'Tables and structures' ).
      WHEN 'DDLS'. rv_title = 'CDS Views'.
      WHEN 'DTEL'. rv_title = lcl_t=>t( d = 'Datenelemente' e = 'Data elements' ).
      WHEN 'DOMA'. rv_title = lcl_t=>t( d = 'Domänen' e = 'Domains' ).
      WHEN 'TTYP'. rv_title = lcl_t=>t( d = 'Tabellentypen' e = 'Table types' ).
      WHEN 'VIEW'. rv_title = 'Views'.
      WHEN 'TRAN'. rv_title = lcl_t=>t( d = 'Transaktionen' e = 'Transactions' ).
      WHEN 'MSAG'. rv_title = lcl_t=>t( d = 'Nachrichtenklassen' e = 'Message classes' ).
      WHEN 'ENQU'. rv_title = lcl_t=>t( d = 'Sperrobjekte' e = 'Lock objects' ).
      WHEN 'SHLP'. rv_title = lcl_t=>t( d = 'Suchhilfen' e = 'Search helps' ).
      WHEN 'DEVC'. rv_title = lcl_t=>t( d = 'Pakete' e = 'Packages' ).
      WHEN 'FUNC'. rv_title = lcl_t=>t( d = 'Funktionsbausteine' e = 'Function modules' ).
      WHEN 'VCLS'. rv_title = lcl_t=>t( d = 'View-Cluster' e = 'View clusters' ).
      WHEN 'SSFO'. rv_title = lcl_t=>t( d = 'Smart Forms' e = 'Smart Forms' ).
      WHEN 'SFPF'. rv_title = lcl_t=>t( d = 'Adobe Forms (Formulare)' e = 'Adobe Forms (forms)' ).
      WHEN 'SFPI'. rv_title = lcl_t=>t( d = 'Adobe Forms (Schnittstellen)' e = 'Adobe Forms (interfaces)' ).
      WHEN OTHERS. rv_title = |{ lcl_t=>t( d = `Objekttyp` e = `Object type` ) } { iv_type }|.
    ENDCASE.
  ENDMETHOD.

  METHOD add_definition.

    DATA lv_ok TYPE abap_bool.

*   Ein IDoc-Segmenttyp traegt im Katalog TABL, weil SAP zu jedem
*   Segment eine gleichnamige Struktur erzeugt. Fuer die Definition ist
*   er aber etwas anderes: als Struktur angelegt kennt WE31 ihn nicht.
    DATA lv_kind TYPE trobjtype.
    lv_kind = iv_type.
    IF lv_kind = 'TABL'.
      DATA lv_seg TYPE edisegment-segtyp.
      lv_seg = iv_name.
      SELECT COUNT(*) FROM edisegment WHERE segtyp = @lv_seg.
      DATA(lv_is_seg) = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).
      IF lv_is_seg = abap_true.
        lv_kind = 'SEGM'.
      ENDIF.
    ENDIF.

    CASE lv_kind.
      WHEN 'DOMA'. lv_ok = def_doma( iv_name = iv_name io_chapter = io_chapter ).
      WHEN 'DTEL'. lv_ok = def_dtel( iv_name = iv_name io_chapter = io_chapter ).
      WHEN 'TABL'. lv_ok = def_tabl( iv_name = iv_name io_chapter = io_chapter ).
      WHEN 'VIEW'. lv_ok = def_view( iv_name = iv_name io_chapter = io_chapter ).
      WHEN 'DDLS'. lv_ok = def_ddls( iv_name = iv_name io_chapter = io_chapter ).
      WHEN 'PROG'. lv_ok = def_prog( iv_name = iv_name io_chapter = io_chapter ).
      WHEN 'CLAS' OR 'INTF'.
        lv_ok = def_clif( iv_type = iv_type iv_name = iv_name io_chapter = io_chapter ).
      WHEN 'FUGR'. lv_ok = def_fugr( iv_name = iv_name io_chapter = io_chapter ).
      WHEN 'MSAG'. lv_ok = def_msag( iv_name = iv_name io_chapter = io_chapter ).
      WHEN 'BDEF' OR 'SRVD' OR 'DDLX'.
        lv_ok = def_wbsrc( iv_type    = iv_type
                           iv_name    = iv_name
                           io_chapter = io_chapter ).
      WHEN 'SRVB'. lv_ok = def_srvb( iv_name = iv_name io_chapter = io_chapter ).
      WHEN 'SEGM'. lv_ok = def_segm( iv_name = iv_name io_chapter = io_chapter ).
      WHEN 'IDOC'. lv_ok = def_idoc( iv_name = iv_name io_chapter = io_chapter ).
      WHEN 'WAPA'. lv_ok = def_wapa( iv_name = iv_name io_chapter = io_chapter ).
      WHEN 'TRAN'. lv_ok = def_tran( iv_name = iv_name io_chapter = io_chapter ).
      WHEN 'VCLS'. lv_ok = def_vcls( iv_name = iv_name io_chapter = io_chapter ).
      WHEN 'SFPI'. lv_ok = def_sfpi( iv_name = iv_name io_chapter = io_chapter ).
      WHEN 'SFPF'. lv_ok = def_sfpf( iv_name = iv_name io_chapter = io_chapter ).
      WHEN OTHERS.
        RETURN.
    ENDCASE.

    IF lv_ok = abap_true.
      mv_n_def = mv_n_def + 1.
*     Die Objektdokumentation faehrt mit den Definitionsdaten, in allen
*     Sprachen - unabhaengig davon, ob sie im lesbaren Dokument
*     angezeigt wird. Bisher kam sie nur ueber den Dokumentationstext
*     des Kapitels, also nur mit angehakter Objektdokumentation und nur
*     in einer Sprache.
      def_docu( iv_kind = lv_kind iv_name = iv_name io_chapter = io_chapter ).
    ENDIF.

  ENDMETHOD.

  METHOD def_doma.

    DATA ls_dd01v TYPE dd01v.
    DATA lt_dd07v TYPE STANDARD TABLE OF dd07v WITH EMPTY KEY.
    DATA lv_obj   TYPE ddobjname.

    lv_obj = iv_name.
    CALL FUNCTION 'DDIF_DOMA_GET'
      EXPORTING  name          = lv_obj
                 state         = 'A'
                 langu         = mv_langu
      IMPORTING  dd01v_wa      = ls_dd01v
      TABLES     dd07v_tab     = lt_dd07v
      EXCEPTIONS illegal_input = 1
                 OTHERS        = 2.
    IF sy-subrc <> 0 OR ls_dd01v-domname IS INITIAL.
      RETURN.
    ENDIF.

    io_chapter->set_definition( iv_kind = 'DOMA'
                                it_head = lcl_attr=>from_struct( ls_dd01v ) ).
    LOOP AT lt_dd07v INTO DATA(ls_dd07v).
      io_chapter->add_defrow( VALUE ty_defrow(
        tag   = 'DD07V'
        attrs = lcl_attr=>from_struct( ls_dd07v ) ) ).
    ENDLOOP.
    rv_ok = abap_true.

  ENDMETHOD.

  METHOD def_dtel.

    DATA ls_dd04v TYPE dd04v.
    DATA lv_obj   TYPE ddobjname.

    lv_obj = iv_name.
    CALL FUNCTION 'DDIF_DTEL_GET'
      EXPORTING  name          = lv_obj
                 state         = 'A'
                 langu         = mv_langu
      IMPORTING  dd04v_wa      = ls_dd04v
      EXCEPTIONS illegal_input = 1
                 OTHERS        = 2.
    IF sy-subrc <> 0 OR ls_dd04v-rollname IS INITIAL.
      RETURN.
    ENDIF.

    io_chapter->set_definition( iv_kind = 'DTEL'
                                it_head = lcl_attr=>from_struct( ls_dd04v ) ).
    rv_ok = abap_true.

  ENDMETHOD.

  METHOD def_tabl.

    DATA ls_dd02v TYPE dd02v.
    DATA ls_dd09v TYPE dd09v.
    DATA lt_dd03p TYPE STANDARD TABLE OF dd03p WITH EMPTY KEY.
    DATA lt_dd05m TYPE STANDARD TABLE OF dd05m WITH EMPTY KEY.
    DATA lt_dd08v TYPE STANDARD TABLE OF dd08v WITH EMPTY KEY.
    DATA lt_dd35v TYPE STANDARD TABLE OF dd35v WITH EMPTY KEY.
    DATA lt_dd36m TYPE STANDARD TABLE OF dd36m WITH EMPTY KEY.
    DATA lt_dd12v TYPE STANDARD TABLE OF dd12v WITH EMPTY KEY.
    DATA lt_dd17v TYPE STANDARD TABLE OF dd17v WITH EMPTY KEY.
    DATA lv_obj   TYPE ddobjname.

    lv_obj = iv_name.
    CALL FUNCTION 'DDIF_TABL_GET'
      EXPORTING  name          = lv_obj
                 state         = 'A'
                 langu         = mv_langu
      IMPORTING  dd02v_wa      = ls_dd02v
                 dd09l_wa      = ls_dd09v
      TABLES     dd03p_tab     = lt_dd03p
                 dd05m_tab     = lt_dd05m
                 dd08v_tab     = lt_dd08v
                 dd12v_tab     = lt_dd12v
                 dd17v_tab     = lt_dd17v
                 dd35v_tab     = lt_dd35v
                 dd36m_tab     = lt_dd36m
      EXCEPTIONS illegal_input = 1
                 OTHERS        = 2.
    IF sy-subrc <> 0 OR ls_dd02v-tabname IS INITIAL.
      RETURN.
    ENDIF.

    io_chapter->set_definition( iv_kind = 'TABL'
                                it_head = lcl_attr=>from_struct( ls_dd02v ) ).

*   Technical settings only exist for a real table, not for a structure.
    IF ls_dd09v-tabname IS NOT INITIAL.
      io_chapter->add_defrow( VALUE ty_defrow(
        tag = 'DD09V' attrs = lcl_attr=>from_struct( ls_dd09v ) ) ).
    ENDIF.

    LOOP AT lt_dd03p INTO DATA(ls_dd03p).
      io_chapter->add_defrow( VALUE ty_defrow(
        tag = 'DD03P' attrs = lcl_attr=>from_struct( ls_dd03p ) ) ).
    ENDLOOP.
    LOOP AT lt_dd05m INTO DATA(ls_dd05m).
      io_chapter->add_defrow( VALUE ty_defrow(
        tag = 'DD05M' attrs = lcl_attr=>from_struct( ls_dd05m ) ) ).
    ENDLOOP.
    LOOP AT lt_dd08v INTO DATA(ls_dd08v).
      io_chapter->add_defrow( VALUE ty_defrow(
        tag = 'DD08V' attrs = lcl_attr=>from_struct( ls_dd08v ) ) ).
    ENDLOOP.
    LOOP AT lt_dd35v INTO DATA(ls_dd35v).
      io_chapter->add_defrow( VALUE ty_defrow(
        tag = 'DD35V' attrs = lcl_attr=>from_struct( ls_dd35v ) ) ).
    ENDLOOP.
    LOOP AT lt_dd36m INTO DATA(ls_dd36m).
      io_chapter->add_defrow( VALUE ty_defrow(
        tag = 'DD36M' attrs = lcl_attr=>from_struct( ls_dd36m ) ) ).
    ENDLOOP.

*   Secondary indexes are objects of their own; DDIF_TABL_PUT does not
*   take them, DDIF_INDX_PUT does. They travel along here and are
*   created after the table stands.
    LOOP AT lt_dd12v INTO DATA(ls_dd12v).
      io_chapter->add_defrow( VALUE ty_defrow(
        tag = 'DD12V' attrs = lcl_attr=>from_struct( ls_dd12v ) ) ).
    ENDLOOP.
    LOOP AT lt_dd17v INTO DATA(ls_dd17v).
      io_chapter->add_defrow( VALUE ty_defrow(
        tag = 'DD17V' attrs = lcl_attr=>from_struct( ls_dd17v ) ) ).
    ENDLOOP.

*   Ein Pflegedialog haengt nicht nur an Views. Eine Tabelle, die in
*   SM30 gepflegt wird, hat ihren TVDIR-Eintrag selbst.
    def_maint( iv_name = iv_name io_chapter = io_chapter ).

    rv_ok = abap_true.

  ENDMETHOD.

  METHOD def_prog.

    DATA ls_trdir TYPE trdir.
    DATA lt_tpool TYPE STANDARD TABLE OF textpool WITH EMPTY KEY.
    DATA lv_prog  TYPE progname.

    lv_prog = iv_name.
    SELECT SINGLE * FROM trdir WHERE name = @lv_prog INTO @ls_trdir.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

*   The source has to be complete here. What the reader gets may be cut
*   short by P_MAXSRC; half a report cannot be inserted anywhere.
    DATA(lt_src) = source_lines( iv_type = 'PROG' iv_name = iv_name ).
    IF lt_src IS INITIAL.
      RETURN.
    ENDIF.
    DATA lv_source TYPE string.
    LOOP AT lt_src INTO DATA(lv_line).
      IF lv_source IS INITIAL AND sy-tabix = 1.
        lv_source = lv_line.
      ELSE.
        lv_source = |{ lv_source }{ cl_abap_char_utilities=>newline }{ lv_line }|.
      ENDIF.
    ENDLOOP.

    io_chapter->set_definition( iv_kind = 'PROG'
                                it_head = lcl_attr=>from_struct( ls_trdir ) ).
    io_chapter->set_defsource( lv_source ).

*   Text elements are part of the program and are stored apart from the
*   source; without them selection texts and list headings are lost.
*   In jeder gepflegten Sprache, nicht nur in der Ausgabesprache. Wer
*   den Report auf Englisch dokumentierte, nahm sonst die deutschen
*   Selektionstexte nicht mit - und umgekehrt. Jede Zeile traegt ihre
*   Sprache in _SPRSL; der Import schreibt sie genau dorthin zurueck.
    SELECT DISTINCT language FROM repotext
      WHERE progname = @lv_prog AND r3state = 'A'
      INTO TABLE @DATA(lt_tplang).
    IF lt_tplang IS INITIAL.
      APPEND VALUE #( language = mv_langu ) TO lt_tplang.
    ENDIF.
    LOOP AT lt_tplang INTO DATA(ls_tpl).
      CLEAR lt_tpool.
      READ TEXTPOOL lv_prog INTO lt_tpool LANGUAGE ls_tpl-language.
      LOOP AT lt_tpool INTO DATA(ls_tp).
        DATA(lt_tpa) = lcl_attr=>from_struct( ls_tp ).
        INSERT VALUE ty_attr( name  = '_SPRSL'
                              value = CONV string( ls_tpl-language ) )
               INTO lt_tpa INDEX 1.
        io_chapter->add_defrow( VALUE ty_defrow( tag = 'TPOOL' attrs = lt_tpa ) ).
      ENDLOOP.
    ENDLOOP.

    SELECT SINGLE text FROM trdirt
      WHERE name = @lv_prog AND sprsl = @mv_langu
      INTO @DATA(lv_title).
    IF sy-subrc = 0 AND lv_title IS NOT INITIAL.
      io_chapter->add_defrow( VALUE ty_defrow(
        tag   = 'TITLE'
        attrs = VALUE ty_attrs(
          ( name = 'SPRSL' value = CONV string( mv_langu ) )
          ( name = 'TEXT'  value = lv_title ) ) ) ).
    ENDIF.

    def_cua( io_chapter = io_chapter iv_prog = lv_prog ).

    rv_ok = abap_true.

  ENDMETHOD.

  METHOD def_wbsrc.

*   Verhaltensdefinition, Service-Definition und Metadata Extension.
*   Alle drei sind Quelltext und werden ueber denselben Operator
*   gelesen: c_data_content liefert einen String, genau wie bei einer
*   CDS-Quelle. Der Unterschied zwischen ihnen ist nur der Objekttyp.
*   Ein Katalogeintrag ist bei diesen Arten kein Beweis, dass es das
*   Objekt gibt: auf S4H stehen reihenweise BDEF- und DDLX-Eintraege in
*   TADIR, deren Inhalt sich nicht laden laesst. Der Lauf darf daran
*   nicht scheitern; lcl_wb faengt alles ab.
    DATA(lo_data) = lcl_wb=>read( iv_type = iv_type iv_name = iv_name ).
    IF lo_data IS NOT BOUND.
      RETURN.
    ENDIF.

    DATA(lv_src) = lcl_wb=>content( lo_data ).
    IF lv_src IS INITIAL.
      RETURN.
    ENDIF.

*   Der Kopf traegt nur Name und Beschreibung. Alles andere am
*   Metadatensatz - UUID, Aenderer, Zeitstempel, Quellsystem - ist
*   systemspezifisch und hat im Dokument nichts verloren.
    DATA lt_head TYPE ty_attrs.
    APPEND VALUE ty_attr( name = 'NAME' value = iv_name ) TO lt_head.
    DATA(lv_desc) = lcl_wb=>description( lo_data ).
    IF lv_desc IS NOT INITIAL.
      APPEND VALUE ty_attr( name = 'DESCRIPTION' value = lv_desc ) TO lt_head.
    ENDIF.

    io_chapter->set_definition( iv_kind = CONV string( iv_type )
                                it_head = lt_head ).
    io_chapter->set_defsource( lv_src ).
    rv_ok = abap_true.

  ENDMETHOD.

  METHOD def_wapa.

*   Eine UI5-Anwendung. Der Rahmen ist eine BSP-Anwendung, die Dateien
*   liegen als deren Seiten - aber nicht so, wie die Seiten-API sie
*   herausgibt. Deren P_XML_SOURCE ist der XML-Rahmen der Seite
*   (<so2:page o="0" x="0" ...>), nicht die Datei: fuer Component.js
*   waren das 365 Bytes. Wer diesen Rahmen kopiert, legt Seiten mit
*   richtigen Namen und richtigen Attributen an, die leer sind - und
*   es faellt beim Anlegen nicht auf, weil alles Sichtbare stimmt.
*
*   Der Inhalt liegt hinter der UI5-Repository-API. Sie kennt auch den
*   Pfadbaum, der nicht in den Seitennamen steht, sondern in einer
*   eigenen Zuordnungsdatei (UI5RepositoryPathMapping.xml) - lange
*   Pfade stehen als Seite unter einem Hashnamen. ADT nimmt denselben
*   Weg; wer daran vorbeigreift, sieht Seiten, aber keine Anwendung.
*
*   Der Inhalt reist als Base64 - eine Regel fuer Text und Binaeres
*   gleichermassen, ohne Raten ueber Kodierungen. Im HTML taucht er nie
*   auf: der HTML-Renderer fasst Definitionsdaten grundsaetzlich nicht an.
    DATA lo_app   TYPE REF TO cl_o2_api_application.
    DATA lo_ui5   TYPE REF TO object.
    DATA ls_attr  TYPE o2applattr.
    DATA lv_appl  TYPE o2applname.

    lv_appl = iv_name.
*   Ein Katalogeintrag ist auch hier kein Beweis: auf S4H stehen
*   WAPA-Eintraege ohne Anwendung dahinter.
    cl_o2_api_application=>load(
      EXPORTING  p_application_name  = lv_appl
      IMPORTING  p_application       = lo_app
      EXCEPTIONS object_not_existing = 1
                 permission_failure  = 2
                 error_occured       = 3
                 OTHERS              = 4 ).
    IF sy-subrc <> 0 OR lo_app IS NOT BOUND.
      RETURN.
    ENDIF.

    lo_app->get_attributes( IMPORTING  p_attributes = ls_attr
                            EXCEPTIONS OTHERS       = 1 ).
    IF sy-subrc <> 0 OR ls_attr-applname IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lt_head) = lcl_attr=>from_struct( ls_attr ).
*   Wer sie angelegt hat, wann, in welchem Paket und in welcher Fassung
*   gehoert dem Quellsystem.
    DELETE lt_head WHERE name = 'AUTHOR'    OR name = 'CREATEDON'
                      OR name = 'CHANGEDBY' OR name = 'CHANGEDON'
                      OR name = 'DEVCLASS'  OR name = 'VERSION'
                      OR name = 'MODIFLANG'.
    io_chapter->set_definition( iv_kind = 'WAPA' it_head = lt_head ).

    TRY.
        DATA(lv_uget) = CONV string( lv_appl ).
        CALL METHOD ('/UI5/CL_UI5_REP_DT')=>('/UI5/IF_UI5_REP_DT~GET_API')
          EXPORTING iv_name        = lv_uget
                    iv_dialog_mode = space
          RECEIVING ro_instance    = lo_ui5.
      CATCH cx_root.
        RETURN.
    ENDTRY.

*   Den Baum abgehen, Ordner zuerst: beim Import muss ein Ordner da
*   sein, bevor eine Datei darin liegen kann. Die Arbeitsliste waechst
*   waehrend der Schleife - deshalb keine LOOP, sondern ein Index, der
*   der Liste hinterherlaeuft.
    DATA lt_todo  TYPE string_table.
    DATA lv_idx   TYPE i.
    DATA lv_total TYPE i.

    APPEND `` TO lt_todo.
    lv_idx = 1.
    WHILE lv_idx <= lines( lt_todo ).
      READ TABLE lt_todo INTO DATA(lv_dir) INDEX lv_idx.
      lv_idx = lv_idx + 1.

      DATA lt_kids TYPE string_table.
      CLEAR lt_kids.
      TRY.
          CALL METHOD lo_ui5->('/UI5/IF_UI5_REP_DT~GET_FOLDER_CHILDREN')
            EXPORTING iv_path     = lv_dir
            RECEIVING rt_children = lt_kids.
        CATCH cx_root.
          CONTINUE.
      ENDTRY.
      SORT lt_kids.

      LOOP AT lt_kids INTO DATA(lv_path).
        DATA lv_fold TYPE abap_bool.
        CLEAR lv_fold.
        TRY.
            CALL METHOD lo_ui5->('/UI5/IF_UI5_REP_DT~CHECK_IS_FOLDER')
              EXPORTING iv_path   = lv_path
              RECEIVING rv_result = lv_fold.
          CATCH cx_root.
            CONTINUE.
        ENDTRY.

        IF lv_fold = abap_true.
          APPEND lv_path TO lt_todo.
          io_chapter->add_defrow( VALUE ty_defrow(
            tag   = 'WAPA_DIR'
            attrs = VALUE #( ( name = 'PATH' value = lv_path ) ) ) ).
          CONTINUE.
        ENDIF.

        DATA lv_cont TYPE xstring.
        DATA lv_mime TYPE string.
        CLEAR: lv_cont, lv_mime.
        TRY.
            CALL METHOD lo_ui5->('/UI5/IF_UI5_REP_DT~GET_FILE')
              EXPORTING iv_path         = lv_path
              IMPORTING ev_file_content = lv_cont
                        ev_mime_type    = lv_mime.
          CATCH cx_root.
            CONTINUE.
        ENDTRY.

        DATA lv_size TYPE i.
        lv_size  = xstrlen( lv_cont ).
        lv_total = lv_total + lv_size.

        io_chapter->add_defrow( VALUE ty_defrow(
          tag   = 'WAPA_FILE'
          attrs = VALUE #( ( name = 'PATH'     value = lv_path )
                           ( name = 'MIMETYPE' value = lv_mime )
                           ( name = 'SIZE'     value = |{ lv_size }| ) )
          src   = cl_http_utility=>encode_x_base64( unencoded = lv_cont ) ) ).
      ENDLOOP.
    ENDWHILE.

    IF lv_total = 0.
      RETURN.
    ENDIF.

    rv_ok = abap_true.

  ENDMETHOD.

  METHOD def_segm.

*   Ein IDoc-Segmenttyp. Im Objektkatalog steht er als TABL, weil SAP
*   zu jedem Segment eine gleichnamige DDIC-Struktur erzeugt - und genau
*   das ist die Falle: als TABL exportiert und importiert entstuende im
*   Zielsystem eine Struktur mit den richtigen Feldern, die WE31 nicht
*   als Segment kennt. Die Segmentdefinition und die Freigabestaende
*   fehlten, ohne dass es jemandem auffiele.
    DATA ls_head TYPE edisegmhd.
    DATA lt_stru TYPE STANDARD TABLE OF edisegstru WITH EMPTY KEY.
    DATA lt_def  TYPE STANDARD TABLE OF edisegmdef WITH EMPTY KEY.
    DATA lv_seg  TYPE edisegmhd-segtyp.
    DATA lv_rc   TYPE sy-subrc.

    lv_seg = iv_name.
    CALL FUNCTION 'SEGMENT_READ'
      EXPORTING  segmenttyp           = lv_seg
      IMPORTING  result               = lv_rc
                 segmentheader        = ls_head
      TABLES     segmentdefinition    = lt_def
                 segmentstructure     = lt_stru
      EXCEPTIONS no_authority         = 1
                 segment_not_existing = 2
                 OTHERS               = 3.
    IF sy-subrc <> 0 OR ls_head-segtyp IS INITIAL.
      RETURN.
    ENDIF.

*   Anlage- und Aenderungsstempel gehoeren dem Quellsystem.
    CLEAR: ls_head-credate, ls_head-cretime,
           ls_head-ldate,   ls_head-ltime.

    io_chapter->set_definition( iv_kind = 'SEGM'
                                it_head = lcl_attr=>from_struct( ls_head ) ).

    SORT lt_stru BY pos.
    LOOP AT lt_stru INTO DATA(ls_stru).
      io_chapter->add_defrow( VALUE ty_defrow(
        tag = 'SEGSTRU' attrs = lcl_attr=>from_struct( ls_stru ) ) ).
    ENDLOOP.

    rv_ok = abap_true.

  ENDMETHOD.

  METHOD def_idoc.

*   Ein IDoc-Basistyp: Kopfdaten und die Segmenthierarchie. Die
*   Hierarchie ist der Baum, den WE30 zeigt - je Zeile ein Segment mit
*   Vatersegment, Ebene, Muss-Kennzeichen und Wiederholbereich.
*
*   Gelesen wird in EDI_IAPI01, weitergegeben wird EDI_IAPI05: die
*   Schreibseite will genau die sechs Felder, die ein Basistyp
*   ausmachen. Was darueber hinaus im Lesesatz steht - Paket, Anleger,
*   Zeitstempel - ist systemspezifisch und faellt beim Umkopieren
*   von selbst weg.
    DATA ls_read TYPE edi_iapi01.
    DATA ls_attr TYPE edi_iapi05.
    DATA lt_syn  TYPE STANDARD TABLE OF edi_iapi02 WITH EMPTY KEY.
    DATA lv_idoc TYPE edi_iapi00-idoctyp.

    lv_idoc = iv_name.
    CALL FUNCTION 'IDOCTYPE_READ'
      EXPORTING  pi_idoctyp         = lv_idoc
                 pi_check_authority = abap_true
      IMPORTING  pe_attributes      = ls_read
      TABLES     pt_syntax          = lt_syn
      EXCEPTIONS object_not_found   = 1
                 no_authority       = 2
                 db_error           = 3
                 OTHERS             = 4.
    IF sy-subrc <> 0 OR lt_syn IS INITIAL.
      RETURN.
    ENDIF.

    MOVE-CORRESPONDING ls_read TO ls_attr.
    ls_attr-idoctyp = iv_name.

    io_chapter->set_definition( iv_kind = 'IDOC'
                                it_head = lcl_attr=>from_struct( ls_attr ) ).

    SORT lt_syn BY nr.
    LOOP AT lt_syn INTO DATA(ls_syn).
      io_chapter->add_defrow( VALUE ty_defrow(
        tag = 'SYNTAX' attrs = lcl_attr=>from_struct( ls_syn ) ) ).
    ENDLOOP.

    rv_ok = abap_true.

  ENDMETHOD.

  METHOD def_srvb.

*   Ein Service-Binding ist kein Quelltext. Es ist eine verschachtelte
*   Struktur mit zwei Tabellenebenen: unter dem Binding stehen Services,
*   unter jedem Service seine Versionen. Der Kopf traegt die Bindungsart
*   (ODATA V2, V4, ...), die beiden Ebenen werden Zeilen - dieselbe Form
*   wie die Feldliste einer Tabelle.
*
*   Die Struktur gehoert der Datenklasse CL_SRVB_OBJECT_DATA, die es erst
*   ab 7.5x gibt. Sie entsteht deshalb zur Laufzeit, und gelesen wird
*   ueber Komponentennamen.
    FIELD-SYMBOLS <ls_all> TYPE any.
    FIELD-SYMBOLS <ls_cnt> TYPE any.
    FIELD-SYMBOLS <lt_srv> TYPE ANY TABLE.
    FIELD-SYMBOLS <lt_ver> TYPE ANY TABLE.

    DATA(lr_all) = lcl_wb=>srvb_data( `TY_OBJECT_DATA` ).
    IF lr_all IS NOT BOUND.
      RETURN.
    ENDIF.
    ASSIGN lr_all->* TO <ls_all>.

    DATA(lo_data) = lcl_wb=>read( iv_type = 'SRVB' iv_name = iv_name ).
    IF lo_data IS NOT BOUND.
      RETURN.
    ENDIF.
    lcl_wb=>all_data( EXPORTING io_data = lo_data
                      CHANGING  cs_data = <ls_all> ).
    IF lcl_wb=>comp( is_data = <ls_all> iv_path = `CONTENT-BIND_TYPE` ) IS INITIAL.
      RETURN.
    ENDIF.

    DATA lt_head TYPE ty_attrs.
    APPEND VALUE ty_attr( name = 'NAME' value = iv_name ) TO lt_head.
*   Die Bezeichnung des Bindings ist ueber diesen Weg nicht zu bekommen:
*   get_description( ) liefert nichts, der Metadatensatz beim Lesen der
*   aktiven Fassung auch nicht. ADT zeigt sie, holt sie also woanders
*   her. Beim Import tritt dann der Objektname an ihre Stelle - das
*   Binding ist damit vollstaendig, nur seine Bezeichnung nicht.
    DATA(lv_desc) = lcl_wb=>description( lo_data ).
    IF lv_desc IS INITIAL.
      lv_desc = lcl_wb=>comp( is_data = <ls_all> iv_path = `METADATA-DESCRIPTION` ).
    ENDIF.
    IF lv_desc IS NOT INITIAL.
      APPEND VALUE ty_attr( name = 'DESCRIPTION' value = lv_desc ) TO lt_head.
    ENDIF.
    APPEND VALUE ty_attr( name  = 'BIND_TYPE'
                          value = lcl_wb=>comp( is_data = <ls_all>
                                                iv_path = `CONTENT-BIND_TYPE` ) ) TO lt_head.
    APPEND VALUE ty_attr( name  = 'BIND_TYPE_CATEGORY'
                          value = lcl_wb=>comp( is_data = <ls_all>
                                                iv_path = `CONTENT-BIND_TYPE_CATEGORY` ) ) TO lt_head.
    APPEND VALUE ty_attr( name  = 'BIND_TYPE_VERSION'
                          value = lcl_wb=>comp( is_data = <ls_all>
                                                iv_path = `CONTENT-BIND_TYPE_VERSION` ) ) TO lt_head.
*   Ob das Binding veroeffentlicht ist, steht als Information im
*   Dokument. Angelegt wird es beim Import trotzdem unveroeffentlicht -
*   Veroeffentlichen stellt einen Dienst nach aussen bereit, und das ist
*   eine Entscheidung, die niemand nebenbei treffen sollte.
    APPEND VALUE ty_attr( name  = 'PUBLISHED'
                          value = COND #( WHEN lcl_wb=>comp( is_data = <ls_all>
                                                             iv_path = `PUBLISHED` ) = abap_true
                                          THEN `true` ELSE `false` ) ) TO lt_head.

    io_chapter->set_definition( iv_kind = 'SRVB' it_head = lt_head ).

    ASSIGN COMPONENT 'CONTENT' OF STRUCTURE <ls_all> TO <ls_cnt>.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    ASSIGN COMPONENT 'SERVICES' OF STRUCTURE <ls_cnt> TO <lt_srv>.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    LOOP AT <lt_srv> ASSIGNING FIELD-SYMBOL(<ls_srv>).
      DATA(lv_sname) = lcl_wb=>comp( is_data = <ls_srv> iv_path = `SERVICE_NAME` ).
      io_chapter->add_defrow( VALUE ty_defrow(
        tag   = 'SRVB_SRV'
        attrs = VALUE ty_attrs(
          ( name = 'SERVICE_NAME' value = lv_sname ) ) ) ).

      ASSIGN COMPONENT 'SERVICE_CONTENT' OF STRUCTURE <ls_srv> TO <lt_ver>.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      LOOP AT <lt_ver> ASSIGNING FIELD-SYMBOL(<ls_ver>).
        DATA lt_va TYPE ty_attrs.
        CLEAR lt_va.
*       Der Servicename steht in jeder Versionszeile mit. Zeilen sind im
*       Dokument eine flache Liste; ohne den Rueckverweis liesse sich
*       beim Import nicht sagen, zu welchem Service eine Version gehoert.
        APPEND VALUE ty_attr( name  = 'SERVICE_NAME'
                              value = lv_sname ) TO lt_va.
        APPEND VALUE ty_attr( name  = 'SERVICE_VERSION'
                              value = lcl_wb=>comp( is_data = <ls_ver>
                                                    iv_path = `SERVICE_VERSION` ) ) TO lt_va.
        DATA(lv_rstate) = lcl_wb=>comp( is_data = <ls_ver> iv_path = `RELEASE_STATE` ).
        IF lv_rstate IS NOT INITIAL.
          APPEND VALUE ty_attr( name  = 'RELEASE_STATE'
                                value = lv_rstate ) TO lt_va.
        ENDIF.
*       Von der Objektreferenz nur der Name. URI und Paket sind
*       systemspezifisch und im Zielsystem ohnehin andere.
        DATA(lv_srvd) = lcl_wb=>comp( is_data = <ls_ver> iv_path = `SRVD_REF-NAME` ).
        IF lv_srvd IS NOT INITIAL.
          APPEND VALUE ty_attr( name  = 'SRVD_NAME'
                                value = lv_srvd ) TO lt_va.
        ENDIF.
        io_chapter->add_defrow( VALUE ty_defrow(
          tag = 'SRVB_VER' attrs = lt_va ) ).
      ENDLOOP.
    ENDLOOP.

    rv_ok = abap_true.

  ENDMETHOD.

  METHOD def_msag.

*   A message class. Without it a report that raises one of its own
*   messages shows the bare key - S:ZBLE_0001:006 - because the runtime
*   cannot resolve the text. That is not a translation gap: a missing
*   language falls back, a missing class has nothing to fall back to.
*
*   Read from T100A and T100 directly, not through RPY_MESSAGE_ID_READ.
*   Its counterpart RPY_MESSAGE_ID_INSERT opens the object catalog popup
*   even for $TMP, which an unattended import cannot answer, so the
*   write side goes to the tables anyway - and a pair that reads one way
*   and writes another is worth nothing.
    DATA lv_arb TYPE t100a-arbgb.

    lv_arb = iv_name.
    SELECT SINGLE * FROM t100a WHERE arbgb = @lv_arb INTO @DATA(ls_head).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    io_chapter->set_definition( iv_kind = 'MSAG'
                                it_head = lcl_attr=>from_struct( ls_head ) ).

*   Every language, not just the output language. This is definition
*   data, not description: a class maintained in English only, exported
*   into a German document, would otherwise arrive without a single
*   message - and the report that raises one shows the bare key again.
    SELECT * FROM t100 WHERE arbgb = @lv_arb
      ORDER BY sprsl, msgnr
      INTO TABLE @DATA(lt_t100).
    IF lt_t100 IS INITIAL.
      RETURN.
    ENDIF.

    LOOP AT lt_t100 INTO DATA(ls_t100).
      io_chapter->add_defrow( VALUE ty_defrow(
        tag = 'T100' attrs = lcl_attr=>from_struct( ls_t100 ) ) ).
    ENDLOOP.

    rv_ok = abap_true.

  ENDMETHOD.

  METHOD def_cua.

*   The GUI status of a program. Menus, function keys, application
*   toolbar and titles are a separate program component - INSERT REPORT
*   carries the source and nothing else. A report that sets its own
*   status runs into CX_SALV_OBJECT_NOT_FOUND or a short dump at the
*   first screen without it.
*
*   RS_CUA_INTERNAL_FETCH and _WRITE are a symmetric pair over eleven
*   tables, the same shape as the DDIF_*_GET/PUT calls elsewhere. Each
*   table becomes one row tag; the header goes in as CUA_ADM.
    DATA lt_sta TYPE STANDARD TABLE OF rsmpe_stat WITH EMPTY KEY.
    DATA lt_fun TYPE STANDARD TABLE OF rsmpe_funt WITH EMPTY KEY.
    DATA lt_men TYPE STANDARD TABLE OF rsmpe_men  WITH EMPTY KEY.
    DATA lt_mtx TYPE STANDARD TABLE OF rsmpe_mnlt WITH EMPTY KEY.
    DATA lt_act TYPE STANDARD TABLE OF rsmpe_act  WITH EMPTY KEY.
    DATA lt_but TYPE STANDARD TABLE OF rsmpe_but  WITH EMPTY KEY.
    DATA lt_pfk TYPE STANDARD TABLE OF rsmpe_pfk  WITH EMPTY KEY.
    DATA lt_set TYPE STANDARD TABLE OF rsmpe_staf WITH EMPTY KEY.
    DATA lt_doc TYPE STANDARD TABLE OF rsmpe_atrt WITH EMPTY KEY.
    DATA lt_tit TYPE STANDARD TABLE OF rsmpe_titt WITH EMPTY KEY.
    DATA lt_biv TYPE STANDARD TABLE OF rsmpe_buts WITH EMPTY KEY.
    DATA ls_adm TYPE rsmpe_adm.
    DATA lv_prg TYPE trdir-name.

    lv_prg = iv_prog.
    CALL FUNCTION 'RS_CUA_INTERNAL_FETCH'
      EXPORTING  program         = lv_prg
                 language        = mv_langu
                 state           = 'A'
      IMPORTING  adm             = ls_adm
      TABLES     sta             = lt_sta
                 fun             = lt_fun
                 men             = lt_men
                 mtx             = lt_mtx
                 act             = lt_act
                 but             = lt_but
                 pfk             = lt_pfk
                 set             = lt_set
                 doc             = lt_doc
                 tit             = lt_tit
                 biv             = lt_biv
      EXCEPTIONS not_found       = 1
                 unknown_version = 2
                 OTHERS          = 3.
*   A program without a status is the normal case, not an error.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    IF lt_sta IS INITIAL AND lt_fun IS INITIAL AND lt_tit IS INITIAL.
      RETURN.
    ENDIF.

    io_chapter->add_defrow( VALUE ty_defrow(
      tag = 'CUA_ADM' attrs = lcl_attr=>from_struct( ls_adm ) ) ).

    FIELD-SYMBOLS <ls_any> TYPE any.
    DATA lr_tab TYPE REF TO data.

    DATA lt_part TYPE STANDARD TABLE OF string WITH EMPTY KEY.
    lt_part = VALUE #( ( `STA` ) ( `FUN` ) ( `MEN` ) ( `MTX` ) ( `ACT` )
                       ( `BUT` ) ( `PFK` ) ( `SET` ) ( `DOC` ) ( `TIT` )
                       ( `BIV` ) ).

    LOOP AT lt_part INTO DATA(lv_part).
      CASE lv_part.
        WHEN `STA`. GET REFERENCE OF lt_sta INTO lr_tab.
        WHEN `FUN`. GET REFERENCE OF lt_fun INTO lr_tab.
        WHEN `MEN`. GET REFERENCE OF lt_men INTO lr_tab.
        WHEN `MTX`. GET REFERENCE OF lt_mtx INTO lr_tab.
        WHEN `ACT`. GET REFERENCE OF lt_act INTO lr_tab.
        WHEN `BUT`. GET REFERENCE OF lt_but INTO lr_tab.
        WHEN `PFK`. GET REFERENCE OF lt_pfk INTO lr_tab.
        WHEN `SET`. GET REFERENCE OF lt_set INTO lr_tab.
        WHEN `DOC`. GET REFERENCE OF lt_doc INTO lr_tab.
        WHEN `TIT`. GET REFERENCE OF lt_tit INTO lr_tab.
        WHEN `BIV`. GET REFERENCE OF lt_biv INTO lr_tab.
      ENDCASE.
      FIELD-SYMBOLS <lt_any> TYPE STANDARD TABLE.
      ASSIGN lr_tab->* TO <lt_any>.
      LOOP AT <lt_any> ASSIGNING <ls_any>.
        io_chapter->add_defrow( VALUE ty_defrow(
          tag   = |CUA_{ lv_part }|
          attrs = lcl_attr=>from_struct( <ls_any> ) ) ).
      ENDLOOP.
    ENDLOOP.

  ENDMETHOD.

  METHOD def_view.

    DATA ls_dd25v TYPE dd25v.
    DATA ls_dd09v TYPE dd09v.
    DATA lt_dd26v TYPE STANDARD TABLE OF dd26v WITH EMPTY KEY.
    DATA lt_dd27p TYPE STANDARD TABLE OF dd27p WITH EMPTY KEY.
    DATA lt_dd28j TYPE STANDARD TABLE OF dd28j WITH EMPTY KEY.
    DATA lt_dd28v TYPE STANDARD TABLE OF dd28v WITH EMPTY KEY.
    DATA lt_dd35v TYPE STANDARD TABLE OF dd35v WITH EMPTY KEY.
    DATA lt_dd36m TYPE STANDARD TABLE OF dd36m WITH EMPTY KEY.
    DATA lv_obj   TYPE ddobjname.

    lv_obj = iv_name.
    CALL FUNCTION 'DDIF_VIEW_GET'
      EXPORTING  name          = lv_obj
                 state         = 'A'
                 langu         = mv_langu
      IMPORTING  dd25v_wa      = ls_dd25v
                 dd09l_wa      = ls_dd09v
      TABLES     dd26v_tab     = lt_dd26v
                 dd27p_tab     = lt_dd27p
                 dd28j_tab     = lt_dd28j
                 dd28v_tab     = lt_dd28v
                 dd35v_tab     = lt_dd35v
                 dd36m_tab     = lt_dd36m
      EXCEPTIONS illegal_input = 1
                 OTHERS        = 2.
    IF sy-subrc <> 0 OR ls_dd25v-viewname IS INITIAL.
      RETURN.
    ENDIF.

    io_chapter->set_definition( iv_kind = 'VIEW'
                                it_head = lcl_attr=>from_struct( ls_dd25v ) ).

    IF ls_dd09v-tabname IS NOT INITIAL.
      io_chapter->add_defrow( VALUE ty_defrow(
        tag = 'DD09V' attrs = lcl_attr=>from_struct( ls_dd09v ) ) ).
    ENDIF.
    LOOP AT lt_dd26v INTO DATA(ls_dd26v).
      io_chapter->add_defrow( VALUE ty_defrow(
        tag = 'DD26V' attrs = lcl_attr=>from_struct( ls_dd26v ) ) ).
    ENDLOOP.
    LOOP AT lt_dd27p INTO DATA(ls_dd27p).
      io_chapter->add_defrow( VALUE ty_defrow(
        tag = 'DD27P' attrs = lcl_attr=>from_struct( ls_dd27p ) ) ).
    ENDLOOP.
    LOOP AT lt_dd28j INTO DATA(ls_dd28j).
      io_chapter->add_defrow( VALUE ty_defrow(
        tag = 'DD28J' attrs = lcl_attr=>from_struct( ls_dd28j ) ) ).
    ENDLOOP.
    LOOP AT lt_dd28v INTO DATA(ls_dd28v).
      io_chapter->add_defrow( VALUE ty_defrow(
        tag = 'DD28V' attrs = lcl_attr=>from_struct( ls_dd28v ) ) ).
    ENDLOOP.
    LOOP AT lt_dd35v INTO DATA(ls_dd35v).
      io_chapter->add_defrow( VALUE ty_defrow(
        tag = 'DD35V' attrs = lcl_attr=>from_struct( ls_dd35v ) ) ).
    ENDLOOP.
    LOOP AT lt_dd36m INTO DATA(ls_dd36m).
      io_chapter->add_defrow( VALUE ty_defrow(
        tag = 'DD36M' attrs = lcl_attr=>from_struct( ls_dd36m ) ) ).
    ENDLOOP.

    def_maint( iv_name = iv_name io_chapter = io_chapter ).

    rv_ok = abap_true.

  ENDMETHOD.

  METHOD def_maint.

*   Der Pflegeeintrag. TVDIR sagt, welche Funktionsgruppe und welche
*   beiden Dynpros den Dialog bilden; TVIMF nennt die Formroutinen zu
*   den Pflegeereignissen, TDDAT die Berechtigungsgruppe.
*
*   Ohne diese drei Zeilen kennt SM30 den View im Zielsystem nicht -
*   auch dann nicht, wenn Funktionsgruppe und Bilder vollstaendig
*   angekommen sind. Erzeugen laesst sich der Eintrag nur ueber SE54,
*   und SE54 ist ein Dialog. Also faehrt er mit.
    DATA lv_tab TYPE tvdir-tabname.

    lv_tab = iv_name.
    SELECT SINGLE * FROM tvdir WHERE tabname = @lv_tab INTO @DATA(ls_tvdir).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    io_chapter->add_defrow( VALUE ty_defrow(
      tag = 'TVDIR' attrs = lcl_attr=>from_struct( ls_tvdir ) ) ).

    SELECT * FROM tvimf WHERE tabname = @lv_tab
      INTO TABLE @DATA(lt_tvimf).
    LOOP AT lt_tvimf INTO DATA(ls_tvimf).
      io_chapter->add_defrow( VALUE ty_defrow(
        tag = 'TVIMF' attrs = lcl_attr=>from_struct( ls_tvimf ) ) ).
    ENDLOOP.

    SELECT SINGLE * FROM tddat WHERE tabname = @lv_tab INTO @DATA(ls_tddat).
    IF sy-subrc = 0.
      io_chapter->add_defrow( VALUE ty_defrow(
        tag = 'TDDAT' attrs = lcl_attr=>from_struct( ls_tddat ) ) ).
    ENDIF.

  ENDMETHOD.

  METHOD def_ddls.

    DATA ls_src TYPE ddddlsrcv.
    DATA lv_ddl TYPE ddlname.

    lv_ddl = iv_name.
    TRY.
        DATA lo_ddr TYPE REF TO object.
        CALL METHOD ('CL_DD_DDL_HANDLER_FACTORY')=>('CREATE')
          RECEIVING handler = lo_ddr.
        CALL METHOD lo_ddr->('IF_DD_DDL_HANDLER~READ')
          EXPORTING name         = lv_ddl
                    get_state    = 'A'
                    withtext     = abap_true
                    langu        = mv_langu
          IMPORTING ddddlsrcv_wa = ls_src.
      CATCH cx_root.
        RETURN.
    ENDTRY.
    IF ls_src-source IS INITIAL.
      RETURN.
    ENDIF.

*   The CDS text is a string. As an attribute value it would not survive
*   the trip: XML turns line breaks inside an attribute into blanks. It
*   therefore travels as an element of its own, like every other source.
    DATA(lt_head) = lcl_attr=>from_struct( ls_src ).
    DELETE lt_head WHERE name = 'SOURCE'.

    io_chapter->set_definition( iv_kind = 'DDLS' it_head = lt_head ).
    io_chapter->set_defsource( ls_src-source ).
    rv_ok = abap_true.

  ENDMETHOD.

  METHOD clif_source.

*   CL_OO_FACTORY hands out the source-based form of a class - the one
*   text that carries definition and implementation together. The
*   generated includes of the class pool would be the other way, and out
*   of them no class can be rebuilt.
    DATA lt_src TYPE rswsourcet.

    TRY.
*       Dynamisch: CL_OO_FACTORY gibt es nicht auf jedem Stand.
        DATA lo_fac  TYPE REF TO object.
        DATA lo_src  TYPE REF TO object.
        DATA lv_clif TYPE seoclsname.
        lv_clif = iv_name.
        CALL METHOD ('CL_OO_FACTORY')=>('CREATE_INSTANCE')
          RECEIVING result = lo_fac.
        CALL METHOD lo_fac->('IF_OO_CLIF_SOURCE_FACTORY~CREATE_CLIF_SOURCE')
          EXPORTING clif_name = lv_clif
                    version   = 'A'
          RECEIVING result    = lo_src.
        CALL METHOD lo_src->('IF_OO_CLIF_SOURCE~GET_SOURCE')
          IMPORTING source = lt_src.
      CATCH cx_root.
        RETURN.
    ENDTRY.

    LOOP AT lt_src INTO DATA(lv_line).
      IF sy-tabix = 1.
        rv_source = lv_line.
      ELSE.
        rv_source = |{ rv_source }{ cl_abap_char_utilities=>newline }{ lv_line }|.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD report_source.

    DATA lt_src TYPE STANDARD TABLE OF string WITH EMPTY KEY.

    READ REPORT iv_prog INTO lt_src.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    LOOP AT lt_src INTO DATA(lv_line).
      IF sy-tabix = 1.
        rv_source = lv_line.
      ELSE.
        rv_source = |{ rv_source }{ cl_abap_char_utilities=>newline }{ lv_line }|.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD def_clif.

    DATA ls_class TYPE vseoclass.
    DATA ls_intf  TYPE vseointerf.
    DATA lv_clif  TYPE seoclsname.

    lv_clif = iv_name.

    DATA(lv_source) = clif_source( iv_name ).
    IF lv_source IS INITIAL.
      RETURN.
    ENDIF.

    IF iv_type = 'CLAS'.
      SELECT SINGLE * FROM vseoclass
        WHERE clsname = @lv_clif AND version = '1' AND langu = @mv_langu
        INTO @ls_class.
      IF sy-subrc <> 0.
*       Without a description in the output language the header is still
*       needed - take it in the fallback language rather than not at all.
        SELECT SINGLE * FROM vseoclass
          WHERE clsname = @lv_clif AND version = '1'
          INTO @ls_class.
      ENDIF.
      IF sy-subrc <> 0.
        RETURN.
      ENDIF.
      io_chapter->set_definition( iv_kind = 'CLAS'
                                  it_head = lcl_attr=>from_struct( ls_class ) ).
    ELSE.
      SELECT SINGLE * FROM vseointerf
        WHERE clsname = @lv_clif AND version = '1' AND langu = @mv_langu
        INTO @ls_intf.
      IF sy-subrc <> 0.
        SELECT SINGLE * FROM vseointerf
          WHERE clsname = @lv_clif AND version = '1'
          INTO @ls_intf.
      ENDIF.
      IF sy-subrc <> 0.
        RETURN.
      ENDIF.
      io_chapter->set_definition( iv_kind = 'INTF'
                                  it_head = lcl_attr=>from_struct( ls_intf ) ).
    ENDIF.

    io_chapter->set_defsource( lv_source ).
    rv_ok = abap_true.

  ENDMETHOD.

  METHOD def_fugr.

    DATA lv_area  TYPE rs38l-area.
    DATA lv_main  TYPE progname.
    DATA lt_incl  TYPE STANDARD TABLE OF progname.
    DATA lt_skip  TYPE STANDARD TABLE OF progname WITH EMPTY KEY.

    lv_area = iv_name.
    lv_main = |SAPL{ iv_name }|.

    SELECT SINGLE areat FROM tlibt
      WHERE spras = @mv_langu AND area = @lv_area
      INTO @DATA(lv_text).
    IF sy-subrc <> 0 AND mv_falb = abap_true.
      SELECT SINGLE areat FROM tlibt
        WHERE spras = @mv_flang AND area = @lv_area
        INTO @lv_text.
    ENDIF.

    io_chapter->set_definition(
      iv_kind = 'FUGR'
      it_head = VALUE ty_attrs(
        ( name = 'AREA'       value = CONV string( iv_name ) )
        ( name = 'SHORT_TEXT' value = CONV string( lv_text ) ) ) ).

*   The includes that hold the function modules are generated when the
*   modules are created; they must not travel as includes as well, or the
*   import would write them twice and the second write would win.
    SELECT funcname, include FROM tfdir
      WHERE pname = @lv_main
      INTO TABLE @DATA(lt_fdir).
    LOOP AT lt_fdir INTO DATA(ls_fdir).
      APPEND |L{ iv_name }U{ ls_fdir-include }| TO lt_skip.
    ENDLOOP.
    APPEND |L{ iv_name }UXX| TO lt_skip.
    APPEND lv_main TO lt_skip.

    CALL FUNCTION 'RS_GET_ALL_INCLUDES'
      EXPORTING  program      = lv_main
      TABLES     includetab   = lt_incl
      EXCEPTIONS not_existent = 1
                 no_program   = 2
                 OTHERS       = 3.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    SORT lt_incl BY table_line.
    LOOP AT lt_incl INTO DATA(lv_incl).
      READ TABLE lt_skip TRANSPORTING NO FIELDS
           WITH KEY table_line = lv_incl.
      IF sy-subrc = 0.
        CONTINUE.
      ENDIF.
      DATA(lv_isrc) = report_source( lv_incl ).
      IF lv_isrc IS INITIAL.
        CONTINUE.
      ENDIF.
      io_chapter->add_defrow( VALUE ty_defrow(
        tag   = 'INCLUDE'
        attrs = VALUE ty_attrs( ( name = 'NAME' value = CONV string( lv_incl ) ) )
        src   = lv_isrc ) ).
    ENDLOOP.

*   Now the function modules. RPY_FUNCTIONMODULE_READ hands out exactly
*   what RPY_FUNCTIONMODULE_INSERT takes in.
    SORT lt_fdir BY funcname.
    LOOP AT lt_fdir INTO ls_fdir.
      def_func( iv_func = ls_fdir-funcname io_chapter = io_chapter ).
    ENDLOOP.

*   Status und Dynpros des Rahmenprogramms. Bei einer von SE54
*   erzeugten Pflegegruppe ist das der eigentliche Pflegedialog: die
*   Bausteine allein rufen nur Bilder auf, die es sonst nicht gibt.
    def_cua( io_chapter = io_chapter iv_prog = lv_main ).
    def_dynp( io_chapter = io_chapter iv_prog = lv_main ).

    rv_ok = abap_true.

  ENDMETHOD.

  METHOD def_docu.

    DATA lv_id   TYPE dokhl-id.
    DATA lv_obj  TYPE dokhl-object.
    DATA lt_ln   TYPE STANDARD TABLE OF tline WITH EMPTY KEY.
    DATA lv_body TYPE string.

    CASE iv_kind.
      WHEN 'PROG'. lv_id = 'RE'.
      WHEN 'DTEL'. lv_id = 'DE'.
      WHEN OTHERS. RETURN.
    ENDCASE.
    lv_obj = iv_name.

    SELECT DISTINCT langu FROM dokhl
      WHERE id = @lv_id AND object = @lv_obj AND typ = 'E'
      INTO TABLE @DATA(lt_dl).

    LOOP AT lt_dl INTO DATA(ls_dl).
      CLEAR: lt_ln, lv_body.
      CALL FUNCTION 'DOCU_GET'
        EXPORTING  id                = lv_id
                   langu             = ls_dl-langu
                   object            = lv_obj
                   typ               = 'E'
        TABLES     line              = lt_ln
        EXCEPTIONS no_docu_on_screen = 1
                   no_docu_self_def  = 2
                   no_docu_temp      = 3
                   ret_code          = 4
                   OTHERS            = 5.
      IF sy-subrc <> 0 OR lt_ln IS INITIAL.
        CONTINUE.
      ENDIF.
*     Format und Zeile getrennt durch einen Tabulator - die Form, die der
*     Import schon kennt. Das ITF-Format bleibt so erhalten.
      LOOP AT lt_ln INTO DATA(ls_ln).
        DATA(lv_one) = |{ ls_ln-tdformat }{ cl_abap_char_utilities=>horizontal_tab }{ ls_ln-tdline }|.
        IF lv_body IS INITIAL.
          lv_body = lv_one.
        ELSE.
          lv_body = |{ lv_body }{ cl_abap_char_utilities=>newline }{ lv_one }|.
        ENDIF.
      ENDLOOP.
      io_chapter->add_defrow( VALUE ty_defrow(
        tag   = 'DOCU'
        attrs = VALUE ty_attrs( ( name = 'LANGU' value = CONV string( ls_dl-langu ) ) )
        src   = lv_body ) ).
    ENDLOOP.

  ENDMETHOD.

  METHOD def_dynp.

*   Ein Dynpro besteht aus Kopf, Containern, Feldern, Ablauflogik und
*   den Parametern der Container. RPY_DYNPRO_READ und _INSERT sind das
*   gleiche symmetrische Paar wie DDIF_*_GET/PUT: was hier gelesen
*   wird, geht drueben unveraendert wieder hinein.
    DATA ls_head TYPE rpy_dyhead.
    DATA lt_cont TYPE dycatt_tab.
    DATA lt_f2c  TYPE dyfatc_tab.
    DATA lt_flow TYPE dyn_flowlist.
    DATA lt_para TYPE STANDARD TABLE OF rpy_dypara WITH EMPTY KEY.
    DATA lv_dnum TYPE d020s-dnum.
    DATA lv_flow TYPE string.
    DATA lt_a    TYPE ty_attrs.

    SELECT dnum FROM d020s WHERE prog = @iv_prog
      INTO TABLE @DATA(lt_dyn).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    SORT lt_dyn BY dnum.
    LOOP AT lt_dyn INTO DATA(ls_dyn).

*     Das Selektionsbild entsteht beim Generieren aus dem Quelltext
*     neu. Mitgenommen wuerde es beim Import ein zweites Mal
*     geschrieben, und das zweite Mal gewinnt.
      IF ls_dyn-dnum = '1000' OR ls_dyn-dnum IS INITIAL.
        CONTINUE.
      ENDIF.

      CLEAR: ls_head, lt_cont, lt_f2c, lt_flow, lt_para.
      lv_dnum = ls_dyn-dnum.
      CALL FUNCTION 'RPY_DYNPRO_READ'
        EXPORTING  progname              = iv_prog
                   dynnr                 = lv_dnum
                   suppress_exist_checks = abap_true
                   suppress_corr_checks  = abap_true
        IMPORTING  header                = ls_head
        TABLES     containers            = lt_cont
                   fields_to_containers  = lt_f2c
                   flow_logic            = lt_flow
                   params                = lt_para
        EXCEPTIONS cancelled             = 1
                   not_found             = 2
                   permission_error      = 3
                   OTHERS                = 4.
      IF sy-subrc <> 0 OR ls_head-screen IS INITIAL.
        CONTINUE.
      ENDIF.

*     Die Ablauflogik ist Quelltext und faehrt als Quelltext mit - als
*     Attributwert wuerden aus den Zeilenumbruechen Leerzeichen.
      CLEAR lv_flow.
      LOOP AT lt_flow INTO DATA(ls_flow).
        IF sy-tabix = 1.
          lv_flow = ls_flow-line.
        ELSE.
          lv_flow = |{ lv_flow }{ cl_abap_char_utilities=>newline }{ ls_flow-line }|.
        ENDIF.
      ENDLOOP.

      io_chapter->add_defrow( VALUE ty_defrow(
        tag   = 'DYNP'
        attrs = lcl_attr=>from_struct( ls_head )
        src   = lv_flow ) ).

*     Container, Felder und Parameter tragen die Dynpronummer nicht bei
*     sich. _DYNNR bindet sie zurueck; der Importer liest es und reicht
*     den Rest unveraendert weiter.
      LOOP AT lt_cont INTO DATA(ls_cont).
        lt_a = lcl_attr=>from_struct( ls_cont ).
        INSERT VALUE ty_attr( name = '_DYNNR' value = ls_head-screen ) INTO lt_a INDEX 1.
        io_chapter->add_defrow( VALUE ty_defrow( tag = 'DYCAT' attrs = lt_a ) ).
      ENDLOOP.
      LOOP AT lt_f2c INTO DATA(ls_f2c).
        lt_a = lcl_attr=>from_struct( ls_f2c ).
        INSERT VALUE ty_attr( name = '_DYNNR' value = ls_head-screen ) INTO lt_a INDEX 1.
        io_chapter->add_defrow( VALUE ty_defrow( tag = 'DYFAT' attrs = lt_a ) ).
      ENDLOOP.
      LOOP AT lt_para INTO DATA(ls_para).
        lt_a = lcl_attr=>from_struct( ls_para ).
        INSERT VALUE ty_attr( name = '_DYNNR' value = ls_head-screen ) INTO lt_a INDEX 1.
        io_chapter->add_defrow( VALUE ty_defrow( tag = 'DYPARA' attrs = lt_a ) ).
      ENDLOOP.

    ENDLOOP.

  ENDMETHOD.

  METHOD def_tran.

*   RPY_TRANSACTION_READ gibt TSTC und TSTCC heraus, den Kurztext aber
*   nicht - der steht in TSTCT und wird getrennt gelesen.
    DATA lt_tstc  TYPE STANDARD TABLE OF tstc WITH EMPTY KEY.
    DATA lt_tstcc TYPE STANDARD TABLE OF tstcc WITH EMPTY KEY.
    DATA lv_tcod  TYPE tstc-tcode.

    lv_tcod = iv_name.
    CALL FUNCTION 'RPY_TRANSACTION_READ'
      EXPORTING  transaction      = lv_tcod
      TABLES     tcodes           = lt_tstc
                 gui_attributes   = lt_tstcc
      EXCEPTIONS permission_error = 1
                 cancelled        = 2
                 not_found        = 3
                 object_not_found = 4
                 OTHERS           = 5.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    READ TABLE lt_tstc INTO DATA(ls_tstc) INDEX 1.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    DATA(lv_text) = read_short_text( iv_type = 'TRAN' iv_name = iv_name ).

    DATA(lt_head) = lcl_attr=>from_struct( ls_tstc ).
    APPEND VALUE ty_attr( name = 'SHORT_TEXT' value = lv_text ) TO lt_head.
    io_chapter->set_definition( iv_kind = 'TRAN' it_head = lt_head ).

    LOOP AT lt_tstcc INTO DATA(ls_tstcc).
      io_chapter->add_defrow( VALUE ty_defrow(
        tag = 'TSTCC' attrs = lcl_attr=>from_struct( ls_tstcc ) ) ).
    ENDLOOP.

*   Eine Parametertransaktion - der uebliche Fall beim Pflegedialog,
*   SM30 mit vorbelegtem Viewnamen - traegt ihre Vorbelegung in TSTCP.
*   Ohne sie steht drueben SM30 mit leerem Bild.
    SELECT SINGLE param FROM tstcp WHERE tcode = @lv_tcod INTO @DATA(lv_param).
    IF sy-subrc = 0 AND lv_param IS NOT INITIAL.
      io_chapter->add_defrow( VALUE ty_defrow(
        tag   = 'TSTCP'
        attrs = VALUE ty_attrs( ( name = 'PARAM' value = CONV string( lv_param ) ) ) ) ).
    ENDIF.

    rv_ok = abap_true.

  ENDMETHOD.

  METHOD def_vcls.

*   Ein View-Cluster ist kein Dictionary-Objekt, sondern ein Eintrag in
*   vier Tabellen: Kopf, Struktur, Strukturabhaengigkeiten und die
*   Feldabhaengigkeiten. VIEWCLUSTER_GET_DEFINITION liest sie am
*   Stueck, VIEWCLUSTER_SAVE_DEFINITION schreibt sie zurueck.
*
*   Kopf und Struktur kommen als Pflegeviews V_VCLDIR und V_VCLSTRUC
*   heraus, die den Text schon enthalten - die Texte brauchen also
*   keinen eigenen Weg.
    DATA ls_dir  TYPE v_vcldir.
    DATA lt_str  TYPE STANDARD TABLE OF v_vclstruc WITH EMPTY KEY.
    DATA lt_dep  TYPE STANDARD TABLE OF v_vclstdep WITH EMPTY KEY.
    DATA lt_mf   TYPE STANDARD TABLE OF v_vclmf WITH EMPTY KEY.
    DATA lv_vcl  TYPE vcl_name.

    lv_vcl = iv_name.
    CALL FUNCTION 'VIEWCLUSTER_GET_DEFINITION'
      EXPORTING  vclname                = lv_vcl
      IMPORTING  vcldir_entry           = ls_dir
      TABLES     vclstruc_tab           = lt_str
                 vclstrudep_tab         = lt_dep
                 vclmf_tab              = lt_mf
      EXCEPTIONS viewcluster_not_found  = 1
                 incomplete_viewcluster = 2
                 OTHERS                 = 3.
    IF sy-subrc <> 0 OR ls_dir-vclname IS INITIAL.
      RETURN.
    ENDIF.

    io_chapter->set_definition( iv_kind = 'VCLS'
                                it_head = lcl_attr=>from_struct( ls_dir ) ).

    LOOP AT lt_str INTO DATA(ls_str).
      io_chapter->add_defrow( VALUE ty_defrow(
        tag = 'VCLSTRUC' attrs = lcl_attr=>from_struct( ls_str ) ) ).
    ENDLOOP.
    LOOP AT lt_dep INTO DATA(ls_dep).
      io_chapter->add_defrow( VALUE ty_defrow(
        tag = 'VCLSTDEP' attrs = lcl_attr=>from_struct( ls_dep ) ) ).
    ENDLOOP.
    LOOP AT lt_mf INTO DATA(ls_mf).
      io_chapter->add_defrow( VALUE ty_defrow(
        tag = 'VCLMF' attrs = lcl_attr=>from_struct( ls_mf ) ) ).
    ENDLOOP.

    rv_ok = abap_true.

  ENDMETHOD.

  METHOD def_func.

    DATA lt_imp TYPE STANDARD TABLE OF rsimp WITH EMPTY KEY.
    DATA lt_cha TYPE STANDARD TABLE OF rscha WITH EMPTY KEY.
    DATA lt_exp TYPE STANDARD TABLE OF rsexp WITH EMPTY KEY.
    DATA lt_tbl TYPE STANDARD TABLE OF rstbl WITH EMPTY KEY.
    DATA lt_exc TYPE STANDARD TABLE OF rsexc WITH EMPTY KEY.
    DATA lt_doc TYPE STANDARD TABLE OF rsfdo WITH EMPTY KEY.
    DATA lt_src TYPE STANDARD TABLE OF rssource WITH EMPTY KEY.
    DATA lv_glob TYPE rs38l-global.
    DATA lv_rem  TYPE rs38l-remote.
    DATA lv_upd  TYPE rs38l-utask.
    DATA lv_bas  TYPE rs38l-basxml_enabled.
    DATA lv_text TYPE tftit-stext.
    DATA lv_fn   TYPE rs38l-name.

    lv_fn = iv_func.
    CALL FUNCTION 'RPY_FUNCTIONMODULE_READ'
      EXPORTING  functionname            = lv_fn
      IMPORTING  global_flag             = lv_glob
                 remote_call             = lv_rem
                 update_task             = lv_upd
                 short_text              = lv_text
                 remote_basxml_supported = lv_bas
      TABLES     import_parameter        = lt_imp
                 changing_parameter      = lt_cha
                 export_parameter        = lt_exp
                 tables_parameter        = lt_tbl
                 exception_list          = lt_exc
                 documentation           = lt_doc
                 source                  = lt_src
      EXCEPTIONS error_message           = 1
                 function_not_found      = 2
                 invalid_name            = 3
                 OTHERS                  = 4.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    DATA lv_body TYPE string.
    LOOP AT lt_src INTO DATA(ls_line).
      IF sy-tabix = 1.
        lv_body = ls_line-line.
      ELSE.
        lv_body = |{ lv_body }{ cl_abap_char_utilities=>newline }{ ls_line-line }|.
      ENDIF.
    ENDLOOP.

    io_chapter->add_defrow( VALUE ty_defrow(
      tag   = 'FUNC'
      attrs = VALUE ty_attrs(
        ( name = 'FUNCNAME'    value = CONV string( iv_func ) )
        ( name = 'SHORT_TEXT'  value = CONV string( lv_text ) )
        ( name = 'GLOBAL_FLAG' value = CONV string( lv_glob ) )
        ( name = 'REMOTE_CALL' value = CONV string( lv_rem ) )
        ( name = 'UPDATE_TASK' value = CONV string( lv_upd ) )
        ( name = 'BASXML'      value = CONV string( lv_bas ) ) )
      src   = lv_body ) ).

*   The parameter structures carry no function module name of their own.
*   _FUNC ties them back; the importer reads it and hands the rest over
*   unchanged - an unknown component is skipped there anyway.
    LOOP AT lt_imp INTO DATA(ls_imp).
      DATA(lt_a) = lcl_attr=>from_struct( ls_imp ).
      INSERT VALUE ty_attr( name = '_FUNC' value = iv_func ) INTO lt_a INDEX 1.
      io_chapter->add_defrow( VALUE ty_defrow( tag = 'RSIMP' attrs = lt_a ) ).
    ENDLOOP.
    LOOP AT lt_cha INTO DATA(ls_cha).
      lt_a = lcl_attr=>from_struct( ls_cha ).
      INSERT VALUE ty_attr( name = '_FUNC' value = iv_func ) INTO lt_a INDEX 1.
      io_chapter->add_defrow( VALUE ty_defrow( tag = 'RSCHA' attrs = lt_a ) ).
    ENDLOOP.
    LOOP AT lt_exp INTO DATA(ls_exp).
      lt_a = lcl_attr=>from_struct( ls_exp ).
      INSERT VALUE ty_attr( name = '_FUNC' value = iv_func ) INTO lt_a INDEX 1.
      io_chapter->add_defrow( VALUE ty_defrow( tag = 'RSEXP' attrs = lt_a ) ).
    ENDLOOP.
    LOOP AT lt_tbl INTO DATA(ls_tbl).
      lt_a = lcl_attr=>from_struct( ls_tbl ).
      INSERT VALUE ty_attr( name = '_FUNC' value = iv_func ) INTO lt_a INDEX 1.
      io_chapter->add_defrow( VALUE ty_defrow( tag = 'RSTBL' attrs = lt_a ) ).
    ENDLOOP.
    LOOP AT lt_exc INTO DATA(ls_exc).
      lt_a = lcl_attr=>from_struct( ls_exc ).
      INSERT VALUE ty_attr( name = '_FUNC' value = iv_func ) INTO lt_a INDEX 1.
      io_chapter->add_defrow( VALUE ty_defrow( tag = 'RSEXC' attrs = lt_a ) ).
    ENDLOOP.
    LOOP AT lt_doc INTO DATA(ls_doc).
      lt_a = lcl_attr=>from_struct( ls_doc ).
      INSERT VALUE ty_attr( name = '_FUNC' value = iv_func ) INTO lt_a INDEX 1.
      io_chapter->add_defrow( VALUE ty_defrow( tag = 'RSFDO' attrs = lt_a ) ).
    ENDLOOP.

  ENDMETHOD.

  METHOD read_short_text.
    " Many objects carry no text in the chosen language. Instead of writing
    " an empty line the code falls back to English - that is the maintenance
    " language for SAP standard and often for customer objects as well.
    rv_text = read_text_lang( iv_type  = iv_type
                              iv_name  = iv_name
                              iv_langu = mv_langu ).
    IF rv_text IS INITIAL AND mv_falb = abap_true AND mv_flang <> mv_langu.
      rv_text = read_text_lang( iv_type  = iv_type
                                iv_name  = iv_name
                                iv_langu = mv_flang ).
    ENDIF.
  ENDMETHOD.
  METHOD read_text_lang.

    CASE iv_type.

      WHEN 'PROG'.
        SELECT SINGLE text FROM trdirt
          WHERE name = @iv_name AND sprsl = @iv_langu INTO @DATA(lv_t1).
        rv_text = lv_t1.

      WHEN 'CLAS' OR 'INTF'.
        SELECT SINGLE descript FROM seoclasstx
          WHERE clsname = @iv_name AND langu = @iv_langu INTO @DATA(lv_t2).
        rv_text = lv_t2.

      WHEN 'TABL' OR 'VIEW' OR 'TTYP'.
        SELECT SINGLE ddtext FROM dd02t
          WHERE tabname = @iv_name AND ddlanguage = @iv_langu INTO @DATA(lv_t3).
        rv_text = lv_t3.

      WHEN 'DTEL'.
        SELECT SINGLE ddtext FROM dd04t
          WHERE rollname = @iv_name AND ddlanguage = @iv_langu INTO @DATA(lv_t4).
        rv_text = lv_t4.

      WHEN 'DOMA'.
        SELECT SINGLE ddtext FROM dd01t
          WHERE domname = @iv_name AND ddlanguage = @iv_langu INTO @DATA(lv_t5).
        rv_text = lv_t5.

      WHEN 'TRAN'.
        SELECT SINGLE ttext FROM tstct
          WHERE tcode = @iv_name AND sprsl = @iv_langu INTO @DATA(lv_t6).
        rv_text = lv_t6.

      WHEN 'FUGR'.
        SELECT SINGLE areat FROM tlibt
          WHERE area = @iv_name AND spras = @iv_langu INTO @DATA(lv_t7).
        rv_text = lv_t7.

      WHEN 'DEVC'.
        SELECT SINGLE ctext FROM tdevct
          WHERE devclass = @iv_name AND spras = @iv_langu INTO @DATA(lv_t8).
        rv_text = lv_t8.

      WHEN 'VCLS'.
        SELECT SINGLE text FROM vcldirt
          WHERE vclname = @iv_name AND spras = @iv_langu INTO @DATA(lv_t9).
        rv_text = lv_t9.

      WHEN 'DDLS' OR 'STOB'.
*       Eine STOB-Entitaet traegt keinen eigenen Text; er steht an der
*       DDL-Quelle, zu der sie gehoert.
        DATA lv_tdl TYPE ddddlsrct-ddlname.
        lv_tdl = iv_name.
        IF iv_type = 'STOB'.
          DATA lv_tob TYPE ddldependency-objectname.
          lv_tob = iv_name.
          SELECT SINGLE ddlname FROM ddldependency
            WHERE objectname = @lv_tob AND objecttype = 'STOB' AND state = 'A'
            INTO @lv_tdl.
        ENDIF.
        SELECT SINGLE ddtext FROM ddddlsrct
          WHERE ddlname = @lv_tdl AND ddlanguage = @iv_langu AND as4local = 'A'
          INTO @DATA(lv_t10).
        rv_text = lv_t10.

      WHEN 'MSAG'.
        DATA lv_tmg TYPE t100t-arbgb.
        lv_tmg = iv_name.
        SELECT SINGLE stext FROM t100t
          WHERE arbgb = @lv_tmg AND sprsl = @iv_langu INTO @DATA(lv_t11).
        rv_text = lv_t11.

      WHEN 'SRVD' OR 'SRVB' OR 'IWSV' OR 'IWMO' OR 'IWVB'.
*       Service-Definition, Service-Binding und die Gateway-Objekte.
*       Ihre Texttabellen gibt es nicht auf jedem Stand, deshalb
*       dynamisch und abgefangen - ein fehlender Text darf den Lauf
*       nicht beenden.
*
*       Die Gateway-Objekte tragen im Katalog Name und Version in einem
*       Feld: technischer Name links, vierstellige Version rechts.
        DATA lv_ttab  TYPE tabname.
        DATA lv_twhr  TYPE string.
        DATA lv_ttech TYPE string.
        DATA lv_tver  TYPE string.
        DATA lv_t12   TYPE c LENGTH 60.
        CLEAR: lv_ttab, lv_twhr, lv_t12.
        CASE iv_type.
          WHEN 'SRVD'.
            lv_ttab = 'SRVDSRCT'.
            lv_twhr = |SRVDNAME = '{ iv_name }' AND VERSION = 'A'|.
          WHEN 'SRVB'.
            lv_ttab = 'SRVB_HEAD_T'.
            lv_twhr = |SRVB_NAME = '{ iv_name }' AND VERSION = 'A'|.
          WHEN 'IWSV'.
            lv_ttech = iv_name(35).
            lv_tver  = iv_name+35(4).
            lv_ttab  = '/IWBEP/I_MGW_SRT'.
            lv_twhr  = |TECHNICAL_NAME = '{ condense( lv_ttech ) }' AND VERSION = '{ lv_tver }'|.
          WHEN 'IWMO'.
            lv_ttech = iv_name(32).
            lv_tver  = iv_name+32(4).
            lv_ttab  = '/IWBEP/I_MGW_OHT'.
            lv_twhr  = |TECHNICAL_NAME = '{ condense( lv_ttech ) }' AND VERSION = '{ lv_tver }'|.
          WHEN 'IWVB'.
            lv_ttech = iv_name(32).
            lv_tver  = iv_name+32(4).
            lv_ttab  = '/IWBEP/I_MGW_VOT'.
            lv_twhr  = |VOCAB_ID = '{ condense( lv_ttech ) }' AND VERSION = '{ lv_tver }'|.
        ENDCASE.
        lv_twhr = |{ lv_twhr } AND LANGUAGE = '{ iv_langu }'|.
        TRY.
            SELECT SINGLE description FROM (lv_ttab) WHERE (lv_twhr) INTO @lv_t12.
            rv_text = lv_t12.
          CATCH cx_root.
            CLEAR rv_text.
        ENDTRY.

      WHEN 'BDEF' OR 'DDLX'.
*       Verhaltensdefinition und Metadata Extension haben keine
*       Texttabelle, die sich lesen liesse. Die Beschreibung haelt der
*       Workbench-Operator - derselbe, ueber den der Quelltext kommt.
        DATA(lo_tdm) = lcl_wb=>read( iv_type = iv_type iv_name = iv_name ).
        IF lo_tdm IS BOUND.
          rv_text = lcl_wb=>description( lo_tdm ).
        ENDIF.

      WHEN 'WAPA'.
*       Eine BSP-/UI5-Anwendung traegt ihre Beschreibung nicht in einer
*       Texttabelle je Sprache, sondern als TEXT im Attributsatz -
*       in der Mastersprache. Sie kommt ueber dieselbe API wie die
*       Definitionsdaten (def_wapa); ein Katalogeintrag ohne Anwendung
*       dahinter liefert dabei nichts. Ohne diesen Zweig bekamen die
*       beiden Reports gar keine Beschreibung, jeder andere Typ schon.
        DATA lo_wapp  TYPE REF TO cl_o2_api_application.
        DATA ls_wattr TYPE o2applattr.
        cl_o2_api_application=>load(
          EXPORTING  p_application_name  = CONV o2applname( iv_name )
          IMPORTING  p_application       = lo_wapp
          EXCEPTIONS object_not_existing = 1
                     permission_failure  = 2
                     error_occured       = 3
                     OTHERS              = 4 ).
        IF sy-subrc = 0 AND lo_wapp IS BOUND.
          lo_wapp->get_attributes( IMPORTING  p_attributes = ls_wattr
                                   EXCEPTIONS OTHERS       = 1 ).
          IF sy-subrc = 0.
            rv_text = ls_wattr-text.
          ENDIF.
        ENDIF.

    ENDCASE.

  ENDMETHOD.

  METHOD read_docu.

    CLEAR mv_last_lang.

    rv_text = read_docu_lang( iv_type  = iv_type
                              iv_name  = iv_name
                              iv_langu = mv_langu ).
    IF rv_text IS NOT INITIAL.
      mv_last_lang = mv_langu.
      RETURN.
    ENDIF.

    " If nothing is maintained in the output language, the fallback language
    " is tried. The language that delivered is then noted on the chapter.
    IF mv_falb = abap_true AND mv_flang IS NOT INITIAL AND mv_flang <> mv_langu.
      rv_text = read_docu_lang( iv_type  = iv_type
                                iv_name  = iv_name
                                iv_langu = mv_flang ).
      IF rv_text IS NOT INITIAL.
        mv_last_lang = mv_flang.
      ENDIF.
    ENDIF.

  ENDMETHOD.

  METHOD read_docu_lang.

    DATA lt_line TYPE STANDARD TABLE OF tline.
    DATA lv_id   TYPE dokhl-id.
    DATA lv_obj  TYPE dokhl-object.

    " Only the types that have a classic object documentation.
    CASE iv_type.
      WHEN 'PROG'. lv_id = 'RE'.
      WHEN 'TRAN'. lv_id = 'TR'.
      WHEN 'DTEL'. lv_id = 'DE'.
      WHEN 'FUNC'. lv_id = 'FU'.
      WHEN 'MSAG'. lv_id = 'NA'.
      WHEN OTHERS. RETURN.
    ENDCASE.

    lv_obj = iv_name.

    CALL FUNCTION 'DOCU_GET'
      EXPORTING
        id                = lv_id
        langu             = iv_langu
        object            = lv_obj
        typ               = 'E'
      TABLES
        line              = lt_line
      EXCEPTIONS
        no_docu_on_screen = 1
        no_docu_self_def  = 2
        no_docu_temp      = 3
        ret_code          = 4
        OTHERS            = 5.

    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    LOOP AT lt_line INTO DATA(ls_line).
      IF rv_text IS INITIAL.
        rv_text = ls_line-tdline.
      ELSE.
        rv_text = |{ rv_text }{ cl_abap_char_utilities=>newline }{ ls_line-tdline }|.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD append_report.

    DATA lt_rep TYPE STANDARD TABLE OF string.

    READ REPORT iv_prog INTO lt_rep.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    IF lines( ct_source ) > 0.
      APPEND |* ---------- { iv_prog } ----------| TO ct_source.
    ENDIF.
    APPEND LINES OF lt_rep TO ct_source.

  ENDMETHOD.

  METHOD source_lines.

    DATA lt_src  TYPE string_table.
    DATA lt_incl TYPE STANDARD TABLE OF progname.
    DATA lv_prog TYPE syrepid.

    CASE iv_type.

      WHEN 'FUNC'.
        " A function module lives in exactly one include of its group.
        lv_prog = func_include( CONV rs38l_fnam( iv_name ) ).
        IF lv_prog IS NOT INITIAL.
          append_report( EXPORTING iv_prog = lv_prog CHANGING ct_source = lt_src ).
        ENDIF.

      WHEN 'PROG'.
        lv_prog = iv_name.
        append_report( EXPORTING iv_prog = lv_prog CHANGING ct_source = lt_src ).

      WHEN 'FUGR'.
        " Frame program of the function group and all its includes
        lv_prog = |SAPL{ iv_name }|.
        CALL FUNCTION 'RS_GET_ALL_INCLUDES'
          EXPORTING
            program      = lv_prog
          TABLES
            includetab   = lt_incl
          EXCEPTIONS
            not_existent = 1
            no_program   = 2
            OTHERS       = 3.
        append_report( EXPORTING iv_prog = lv_prog CHANGING ct_source = lt_src ).
        LOOP AT lt_incl INTO DATA(ls_i1).
          append_report( EXPORTING iv_prog = ls_i1
                         CHANGING  ct_source = lt_src ).
        ENDLOOP.

      WHEN 'CLAS' OR 'INTF'.
*       Die generierten Includes des Klassenpools (CCDEF, CCIMP, CU, CO,
*       CI ...) stehen in interner Reihenfolge - Implementierung vor
*       Definition, ohne CLASS ... IMPLEMENTATION und ohne ENDCLASS, mit
*       leeren Standard-Includes als Rauschen. Aus ihnen laesst sich
*       keine Klasse nachbauen. Die quelltextbasierte Fassung von
*       CL_OO_FACTORY (dieselbe, die auch der Reimport ueber def_clif
*       liest) traegt Definition und Implementierung in einer Quelle
*       zusammen - das ist die Kopiervorlage.
        DATA(lv_clifsrc) = clif_source( iv_name ).
        IF lv_clifsrc IS NOT INITIAL.
          SPLIT lv_clifsrc AT cl_abap_char_utilities=>newline
                INTO TABLE lt_src.
        ENDIF.

      WHEN 'BDEF' OR 'SRVD' OR 'DDLX'.
*       Verhaltensdefinition, Service-Definition und Metadata Extension
*       sind Quelltext wie eine CDS-View, stehen aber in keiner Tabelle,
*       die sich direkt lesen liesse. Sie kommen ueber den
*       Workbench-Operator - denselben, den die Definitionsdaten nutzen.
        DATA lv_wsrc TYPE string.
        CLEAR lv_wsrc.
        DATA(lo_sdm) = lcl_wb=>read( iv_type = iv_type iv_name = iv_name ).
        IF lo_sdm IS BOUND.
          lv_wsrc = lcl_wb=>content( lo_sdm ).
        ENDIF.
        IF lv_wsrc IS NOT INITIAL.
          REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf
                  IN lv_wsrc WITH cl_abap_char_utilities=>newline.
          SPLIT lv_wsrc AT cl_abap_char_utilities=>newline INTO TABLE lt_src.
        ENDIF.

      WHEN 'DDLS'.
        DATA lv_ddl TYPE ddddlsrc-ddlname.
        lv_ddl = iv_name.
        SELECT SINGLE source FROM ddddlsrc
          WHERE ddlname = @lv_ddl AND as4local = 'A'
          INTO @DATA(lv_cds).
        IF sy-subrc = 0 AND lv_cds IS NOT INITIAL.
          " The CDS source is stored with CRLF; without removing the
          " carriage return it would stay at the end of every line.
          REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf
                  IN lv_cds WITH cl_abap_char_utilities=>newline.
          SPLIT lv_cds AT cl_abap_char_utilities=>newline INTO TABLE lt_src.
        ENDIF.

      WHEN 'SSFO'.
*       Ein Smart Form hat keinen zusammenhaengenden Quelltext. Was einem
*       Quelltext am naechsten kommt, ist das ABAP der Form: die globalen
*       Typdefinitionen, die globalen Routinen samt Initialisierung und
*       das Coding der Code-Knoten. Zusammengetragen ergibt das einen
*       lesbaren Block - und speist zugleich die Aufrufsuche, die daraus
*       Funktionsbausteine, Tabellen und Klassen der Form erkennt.
        DATA(lo_sf2) = ssfo_form( iv_name ).
        IF lo_sf2 IS NOT BOUND.
          RETURN.
        ENDIF.
        APPEND |* Smart Form { iv_name }| TO lt_src.
        APPEND `` TO lt_src.
        IF lo_sf2->gtypes IS NOT INITIAL.
          APPEND |*--- { lcl_t=>t( d = 'Globale Typen' e = 'Global types' ) } ---| TO lt_src.
          LOOP AT lo_sf2->gtypes INTO DATA(lv_gt).
            APPEND lv_gt TO lt_src.
          ENDLOOP.
          APPEND `` TO lt_src.
        ENDIF.
        IF lo_sf2->gcoding IS NOT INITIAL.
          APPEND |*--- { lcl_t=>t( d = 'Globale Routinen / Initialisierung'
                                   e = 'Global routines / initialization' ) } ---| TO lt_src.
          LOOP AT lo_sf2->gcoding INTO DATA(lv_gc).
            APPEND lv_gc TO lt_src.
          ENDLOOP.
          APPEND `` TO lt_src.
        ENDIF.
        DATA lt_cnodes TYPE string_table.
        CLEAR lt_cnodes.
        LOOP AT lo_sf2->varheader INTO DATA(ls_vhs).
          ssfo_code( EXPORTING io_node = ls_vhs-pagetree
                     CHANGING  ct_src  = lt_cnodes ).
        ENDLOOP.
        IF lt_cnodes IS NOT INITIAL.
          APPEND LINES OF lt_cnodes TO lt_src.
        ENDIF.

      WHEN 'SFPI'.
*       Eine Adobe-Form-Schnittstelle hat keinen zusammenhaengenden
*       Quelltext. Was einem Quelltext am naechsten kommt, sind die
*       globalen Typen, die Initialisierung und die Formularroutinen der
*       Schnittstelle. Zusammengetragen ergibt das einen lesbaren Block -
*       und speist zugleich die Aufrufsuche.
        DATA(lt_isrc) = sfpi_source( iv_name ).
        IF lt_isrc IS NOT INITIAL.
          APPEND |* Adobe Form - { lcl_t=>t( d = 'Schnittstelle' e = 'Interface' ) } { iv_name }| TO lt_src.
          APPEND `` TO lt_src.
          APPEND LINES OF lt_isrc TO lt_src.
        ENDIF.

      WHEN 'SFPF'.
*       Der Code eines Adobe-Formulars liegt nicht im Formular selbst,
*       sondern in seiner Schnittstelle. Deren globale Typen,
*       Initialisierung und Formularroutinen werden ueber den
*       Schnittstellennamen aufgesammelt.
        DATA(lo_fsrc) = sfpf_form( iv_name ).
        IF lo_fsrc IS BOUND.
          DATA(lv_ifsrc) = lo_fsrc->get_interface_name( ).
          IF lv_ifsrc IS NOT INITIAL.
            DATA(lt_fsrc) = sfpi_source( CONV sobj_name( lv_ifsrc ) ).
            IF lt_fsrc IS NOT INITIAL.
              APPEND |* Adobe Form { iv_name } - { lcl_t=>t( d = 'Schnittstelle' e = 'Interface' ) } { lv_ifsrc }| TO lt_src.
              APPEND `` TO lt_src.
              APPEND LINES OF lt_fsrc TO lt_src.
            ENDIF.
          ENDIF.
        ENDIF.

      WHEN OTHERS.
        RETURN.

    ENDCASE.

    rt_source = lt_src.

  ENDMETHOD.

  METHOD ssfo_form.
*   Ein Smart Form wird ueber das Objektmodell des Form Builders gelesen.
*   CL_SSF_FB_SMART_FORM=>LOAD baut aus der Ablage den vollstaendigen
*   Baum auf - denselben, den auch SE80/SMARTFORMS anzeigt. Zuerst wird
*   die aktive Fassung versucht; existiert keine, die gespeicherte. LOAD
*   legt im SHOW-Modus eine Anzeigesperre an, die sofort wieder
*   freigegeben wird - die geladenen Daten bleiben dabei erhalten.
    DATA lv_formname TYPE tdsfname.
    DATA lv_rc       TYPE i.
    lv_formname = iv_name.

    TRY.
        DATA(lo_form) = NEW cl_ssf_fb_smart_form( ).
        TRY.
            lo_form->load( EXPORTING im_formname = lv_formname
                                     im_active   = 'X' ).
          CATCH cx_ssf_fb.
*           Keine aktive Fassung: die gespeicherte lesen.
            lo_form = NEW cl_ssf_fb_smart_form( ).
            lo_form->load( EXPORTING im_formname = lv_formname ).
        ENDTRY.
        TRY.
            lo_form->dequeue( EXPORTING formname = lv_formname
                              IMPORTING rval     = lv_rc ).
          CATCH cx_ssf_fb.
        ENDTRY.
        ro_form = lo_form.
      CATCH cx_ssf_fb.
        CLEAR ro_form.
    ENDTRY.
  ENDMETHOD.

  METHOD ssfo_type_label.
*   Die zweistelligen Knotentypen aus der Typgruppe CSSF, lesbar gemacht.
    CASE iv_type.
      WHEN 'RP'. rv_label = lcl_t=>t( d = 'Seitenbaum-Wurzel' e = 'Page tree root' ).
      WHEN 'PA'. rv_label = lcl_t=>t( d = 'Seite'             e = 'Page' ).
      WHEN 'WI'. rv_label = lcl_t=>t( d = 'Fenster'           e = 'Window' ).
      WHEN 'RC'. rv_label = lcl_t=>t( d = 'Ablaufsteuerung'   e = 'Flow logic' ).
      WHEN 'TI'. rv_label = lcl_t=>t( d = 'Text'              e = 'Text' ).
      WHEN 'GR'. rv_label = lcl_t=>t( d = 'Grafik'            e = 'Graphic' ).
      WHEN 'AD'. rv_label = lcl_t=>t( d = 'Adresse'           e = 'Address' ).
      WHEN 'CM'. rv_label = lcl_t=>t( d = 'Kommando'          e = 'Command' ).
      WHEN 'CO'. rv_label = lcl_t=>t( d = 'Code'              e = 'Code' ).
      WHEN 'CD'. rv_label = lcl_t=>t( d = 'Bedingung'         e = 'Condition' ).
      WHEN 'SE'. rv_label = lcl_t=>t( d = 'Ausgabebereich'    e = 'Section' ).
      WHEN 'EV'. rv_label = lcl_t=>t( d = 'Ereignis'          e = 'Event' ).
      WHEN 'RE'. rv_label = lcl_t=>t( d = 'Referenz'          e = 'Reference' ).
      WHEN 'NO'. rv_label = lcl_t=>t( d = 'Knoten'            e = 'Node' ).
      WHEN OTHERS. rv_label = iv_type.
    ENDCASE.
  ENDMETHOD.

  METHOD ssfo_tree.
*   Ein Knoten und darunter, rekursiv, seine Nachfolger (SUCC). Name und
*   Beschreibung stehen im angehaengten Objekt (CL_SSF_FB_SF_OBJECT);
*   Wurzel- und Steuerknoten tragen keins - dort spricht der Typ. Die
*   Gliederungsnummer bildet die Hierarchie ohne Einrueckung ab, damit
*   sie in jedem Ausgabeformat (HTML wie DOCX) erhalten bleibt.
    IF io_node IS NOT BOUND.
      RETURN.
    ENDIF.

    DATA lv_nname TYPE string.
    DATA lv_ncapt TYPE string.
    IF io_node->obj IS BOUND.
      TRY.
          DATA(lo_sfo) = CAST cl_ssf_fb_sf_object( io_node->obj ).
*         SSFNAME ist eine Struktur (INAME/VARI); der Objektname ist INAME.
          lv_nname = lo_sfo->name-iname.
          lv_ncapt = lo_sfo->caption.
        CATCH cx_sy_move_cast_error.
      ENDTRY.
    ENDIF.

    DATA(lv_type) = ssfo_type_label( io_node->nodetype ).
    DATA(lv_disp) = COND string( WHEN lv_ncapt IS NOT INITIAL THEN lv_ncapt
                                 WHEN lv_nname IS NOT INITIAL THEN lv_nname
                                 ELSE lv_type ).
    DATA(lv_roll) = lv_type.
    IF lv_ncapt IS NOT INITIAL AND lv_nname IS NOT INITIAL.
      lv_roll = |{ lv_type } ({ lv_nname })|.
    ENDIF.

    APPEND VALUE ty_field(
      name     = condense( |{ iv_outline }  { lv_disp }| )
      rollname = lv_roll ) TO ct_field.

    DATA lv_i   TYPE i.
    DATA lv_sub TYPE string.
    LOOP AT io_node->succ INTO DATA(lo_succ).
      IF lo_succ IS NOT BOUND.
        CONTINUE.
      ENDIF.
      lv_i = lv_i + 1.
      IF iv_outline IS INITIAL.
        lv_sub = |{ lv_i }|.
      ELSE.
        lv_sub = |{ iv_outline }.{ lv_i }|.
      ENDIF.
      ssfo_tree( EXPORTING io_node = lo_succ iv_outline = lv_sub
                 CHANGING  ct_field = ct_field ).
    ENDLOOP.
  ENDMETHOD.

  METHOD ssfo_code.
*   Sammelt rekursiv das ABAP der Code-Knoten. Der Zeilentyp von CODE ist
*   ein 132 Zeichen breiter Text (TDSFCLINE), also unmittelbar Quelltext.
    IF io_node IS NOT BOUND.
      RETURN.
    ENDIF.

    IF io_node->nodetype = 'CO' AND io_node->obj IS BOUND.
      TRY.
          DATA(lo_code) = CAST cl_ssf_fb_code( io_node->obj ).
          DATA(lv_hdr)  = |*--- { lcl_t=>t( d = 'Code-Knoten' e = 'Code node' ) }: { lo_code->name-iname }|.
          IF lo_code->caption IS NOT INITIAL.
            lv_hdr = |{ lv_hdr } ({ lo_code->caption })|.
          ENDIF.
          APPEND lv_hdr TO ct_src.
          LOOP AT lo_code->code INTO DATA(lv_cline).
            APPEND lv_cline TO ct_src.
          ENDLOOP.
          APPEND `` TO ct_src.
        CATCH cx_sy_move_cast_error.
      ENDTRY.
    ENDIF.

    LOOP AT io_node->succ INTO DATA(lo_succ).
      ssfo_code( EXPORTING io_node = lo_succ CHANGING ct_src = ct_src ).
    ENDLOOP.
  ENDMETHOD.

  METHOD def_sfpi.
*   Reimportfaehige Definitionsdaten einer Adobe-Form-Schnittstelle.
*   Anders als bei DDIC-Objekten gibt es keine lesbare Tabelle: Parameter,
*   globale Definitionen und Coding kommen aus dem Objektmodell. Parameter
*   und Datenzeilen reisen als name/value-Zeilen (from_struct), Coding als
*   Quelltextbloecke (src). put_sfpi schreibt genau diese ueber
*   CL_FP_WB_INTERFACE wieder zurueck. Standardparameter (DOCPARAMS,
*   FORMOUTPUT) sind von der API bereits herausgefiltert.
    DATA(lo_data) = sfpi_ifc_data( iv_name ).
    IF lo_data IS NOT BOUND.
      RETURN.
    ENDIF.

    DATA lt_head TYPE ty_attrs.
    APPEND VALUE ty_attr( name = 'NAME' value = iv_name ) TO lt_head.
    DATA(lv_desc) = read_short_text( iv_type = 'SFPI' iv_name = iv_name ).
    IF lv_desc IS NOT INITIAL.
      APPEND VALUE ty_attr( name = 'DESCRIPTION' value = lv_desc ) TO lt_head.
    ENDIF.
*   Der Schnittstellentyp (neu / XSD / SF-kompatibel) muss erhalten
*   bleiben - er bestimmt das Parametermodell.
    DATA(lv_iftype) = lo_data->get_interface( )->get_interface_type( ).
    APPEND VALUE ty_attr( name = 'IFTYPE' value = lv_iftype ) TO lt_head.
    io_chapter->set_definition( iv_kind = 'SFPI' it_head = lt_head ).

*   Schnittstellenparameter je Richtung (Import/Export/Tabelle/Ausnahme).
    DATA(lo_par) = lo_data->get_parameters( ).
    LOOP AT lo_par->get_import_parameters( ) INTO DATA(ls_pi).
      IF ls_pi-standard = abap_true. CONTINUE. ENDIF.
      io_chapter->add_defrow( VALUE ty_defrow( tag = 'PAR_I' attrs = lcl_attr=>from_struct( ls_pi ) ) ).
    ENDLOOP.
    LOOP AT lo_par->get_export_parameters( ) INTO DATA(ls_pe).
      IF ls_pe-standard = abap_true. CONTINUE. ENDIF.
      io_chapter->add_defrow( VALUE ty_defrow( tag = 'PAR_E' attrs = lcl_attr=>from_struct( ls_pe ) ) ).
    ENDLOOP.
    LOOP AT lo_par->get_table_parameters( ) INTO DATA(ls_pt).
      IF ls_pt-standard = abap_true. CONTINUE. ENDIF.
      io_chapter->add_defrow( VALUE ty_defrow( tag = 'PAR_T' attrs = lcl_attr=>from_struct( ls_pt ) ) ).
    ENDLOOP.
    LOOP AT lo_par->get_exceptions( ) INTO DATA(ls_px).
      io_chapter->add_defrow( VALUE ty_defrow( tag = 'PAR_X' attrs = lcl_attr=>from_struct( ls_px ) ) ).
    ENDLOOP.

*   Globale Definitionen: Daten und Feldsymbole als Zeilen, Typen als
*   Quelltextblock.
    DATA(lo_gd) = lo_data->get_global_definitions( ).
    LOOP AT lo_gd->get_global_data( ) INTO DATA(ls_gd).
      io_chapter->add_defrow( VALUE ty_defrow( tag = 'GDATA' attrs = lcl_attr=>from_struct( ls_gd ) ) ).
    ENDLOOP.
    LOOP AT lo_gd->get_fieldsymbols( ) INTO DATA(ls_fs).
      io_chapter->add_defrow( VALUE ty_defrow( tag = 'FSYM' attrs = lcl_attr=>from_struct( ls_fs ) ) ).
    ENDLOOP.
    def_sfp_code_row( io_chapter = io_chapter iv_tag = 'C_TYPES' it_code = lo_gd->get_types( ) ).

*   Coding: Initialisierung und Formularroutinen als Quelltext,
*   Initialisierungsparameter als Zeilen.
    DATA(lo_code) = lo_data->get_coding( ).
    def_sfp_code_row( io_chapter = io_chapter iv_tag = 'C_INIT'  it_code = lo_code->get_init_coding( ) ).
    def_sfp_code_row( io_chapter = io_chapter iv_tag = 'C_FORMS' it_code = lo_code->get_forms_coding( ) ).
    LOOP AT lo_code->get_init_input_params( ) INTO DATA(ls_ip).
      DATA(lt_ipa) = lcl_attr=>from_struct( ls_ip ).
      IF lt_ipa IS NOT INITIAL.
        io_chapter->add_defrow( VALUE ty_defrow( tag = 'CP_IN' attrs = lt_ipa ) ).
      ENDIF.
    ENDLOOP.
    LOOP AT lo_code->get_init_output_params( ) INTO DATA(ls_op).
      DATA(lt_opa) = lcl_attr=>from_struct( ls_op ).
      IF lt_opa IS NOT INITIAL.
        io_chapter->add_defrow( VALUE ty_defrow( tag = 'CP_OUT' attrs = lt_opa ) ).
      ENDIF.
    ENDLOOP.

    rv_ok = abap_true.
  ENDMETHOD.

  METHOD def_sfp_code_row.
*   Ein Coding-Block (Typen, Initialisierung, Formularroutinen) wird - um
*   Nachlaufleerzeilen bereinigt - als ein einziger Quelltext-src einer
*   Definitionszeile abgelegt. put_sfpi teilt ihn beim Import wieder in
*   Zeilen. Ein leerer Block erzeugt keine Zeile.
    DATA(lt) = sfp_trim_code( it_code ).
    IF lt IS INITIAL.
      RETURN.
    ENDIF.
    CONCATENATE LINES OF lt INTO DATA(lv_src)
                SEPARATED BY cl_abap_char_utilities=>newline.
    io_chapter->add_defrow( VALUE ty_defrow( tag = iv_tag src = lv_src ) ).
  ENDMETHOD.

  METHOD def_sfpf.
*   Reimportfaehige Definitionsdaten eines Adobe-Formulars. Kontext,
*   Layout und Formulareigenschaften reisen nicht als einzelne Zeilen,
*   sondern in der SAP-eigenen Serialisierung (CL_FP_HELPER=>
*   CONVERT_FORM_TO_XSTRING) - demselben Byte-Strom, den die Kopier-
*   funktion der Transaktion SFP verwendet. Nur so ist der Round-Trip
*   verlustfrei: der Kontextbaum mit generierten und manuellen Knoten,
*   allen Bindungen, Bedingungen und Beschreibungstexten sowie das
*   XFA-/DOCX-Layout kommen 1:1 zurueck, ohne dass das Formularmodell
*   hier nachgebaut werden muesste. Der Kopf traegt die Eigenschaften
*   zusaetzlich im Klartext - lesbar, und damit die Umbenennung beim
*   Import (Formular-, Schnittstellen-, Handlername) greifen kann.
    DATA(lo_form) = sfpf_form( iv_name ).
    IF lo_form IS NOT BOUND.
      RETURN.
    ENDIF.

    DATA lv_blob TYPE xstring.
    TRY.
        lv_blob = cl_fp_helper=>convert_form_to_xstring( i_form = lo_form ).
      CATCH cx_root.
        RETURN.
    ENDTRY.
    IF lv_blob IS INITIAL.
      RETURN.
    ENDIF.

    DATA lt_head TYPE ty_attrs.
    APPEND VALUE ty_attr( name = 'NAME' value = iv_name ) TO lt_head.
    DATA(lv_desc) = read_short_text( iv_type = 'SFPF' iv_name = iv_name ).
    IF lv_desc IS NOT INITIAL.
      APPEND VALUE ty_attr( name = 'DESCRIPTION' value = lv_desc ) TO lt_head.
    ENDIF.
    APPEND VALUE ty_attr( name  = 'INTERFACE'
                          value = CONV string( lo_form->get_interface_name( ) ) ) TO lt_head.
    APPEND VALUE ty_attr( name  = 'FORM_TYPE'
                          value = CONV string( lo_form->get_form_type( ) ) ) TO lt_head.
    DATA(lo_lay) = lo_form->get_layout( ).
    IF lo_lay IS BOUND.
      APPEND VALUE ty_attr( name  = 'FORM_TECH'
                            value = CONV string( lo_lay->get_form_tech( ) ) ) TO lt_head.
      APPEND VALUE ty_attr( name  = 'LAYOUT_TYPE'
                            value = CONV string( lo_lay->get_layout_type( ) ) ) TO lt_head.
    ENDIF.
    DATA(lv_offh) = lo_form->get_offline_handler( ).
    IF lv_offh IS NOT INITIAL.
      APPEND VALUE ty_attr( name = 'OFFLINE_HANDLER' value = CONV string( lv_offh ) ) TO lt_head.
    ENDIF.
    io_chapter->set_definition( iv_kind = 'SFPF' it_head = lt_head ).

    io_chapter->add_defrow( VALUE ty_defrow(
      tag   = 'FORM_DATA'
      attrs = VALUE #( ( name = 'SIZE' value = |{ xstrlen( lv_blob ) }| ) )
      src   = cl_http_utility=>encode_x_base64( unencoded = lv_blob ) ) ).

*   Die Schnittstelle muss mitwandern - das Formular haengt an ihr. Sie
*   reist als Unterkapitel mit eigenen Reimport-Definitionsdaten. So legt
*   der Import sie VOR dem Formular an (Seq 17 < 18) und die Umbenennung
*   zieht Formular, Schnittstelle UND die INTERFACE-Referenz konsistent
*   mit (Formular und Schnittstelle teilen sich denselben Namen).
    DATA(lv_ifname) = CONV sobj_name( lo_form->get_interface_name( ) ).
    IF lv_ifname IS NOT INITIAL.
      DATA(lo_ifchap) = NEW lcl_chapter( iv_id    = |{ io_chapter->get_id( ) }.1|
                                         iv_level = io_chapter->get_level( ) + 1
                                         iv_type  = 'OBJECT'
                                         iv_title = CONV string( lv_ifname ) ).
      SELECT SINGLE devclass, author FROM tadir
        WHERE pgmid = 'R3TR' AND object = 'SFPI' AND obj_name = @lv_ifname
        INTO ( @DATA(lv_ipack), @DATA(lv_iauth) ).
      lo_ifchap->set_reference( VALUE ty_reference( activity = 'SFPI'
                                                    docu_id  = CONV string( lv_iauth )
                                                    tcode    = CONV string( lv_ipack ) ) ).
      IF def_sfpi( iv_name = lv_ifname io_chapter = lo_ifchap ) = abap_true.
        io_chapter->add_child( lo_ifchap ).
      ENDIF.
    ENDIF.

    rv_ok = abap_true.
  ENDMETHOD.

  METHOD sfpf_form.
*   Ein Adobe-Formular wird ueber das Objektmodell der Form-Workbench
*   gelesen. CL_FP_WB_FORM=>LOAD baut aus der Ablage (Kontext-XML) den
*   vollstaendigen Baum auf - denselben, den auch die Transaktion SFP
*   anzeigt. Im Lesemodus wird keine exklusive Sperre gesetzt.
    DATA lv_formname TYPE fpname.
    lv_formname = iv_name.
    TRY.
        DATA(lo_wbf) = cl_fp_wb_form=>load( i_name = lv_formname
                                            i_mode = if_fp_wb_object=>c_mode_read ).
        ro_form ?= lo_wbf->if_fp_wb_object~get_object( ).
      CATCH cx_root.
        CLEAR ro_form.
    ENDTRY.
  ENDMETHOD.

  METHOD sfpi_ifc_data.
*   Die Schnittstellendaten (Parameter, globale Definitionen, Coding)
*   liegen als XML in der Ablage und werden ueber CL_FP_WB_INTERFACE=>LOAD
*   in das Objektmodell deserialisiert. Die Standardparameter (DOCPARAMS,
*   FORMOUTPUT ...) sind dabei bereits herausgefiltert.
    DATA lv_ifname TYPE fpname.
    lv_ifname = iv_name.
    TRY.
        DATA(lo_wbi) = cl_fp_wb_interface=>load( i_name = lv_ifname
                                                 i_mode = if_fp_wb_object=>c_mode_read ).
        DATA(lo_ifc) = CAST if_fp_interface( lo_wbi->if_fp_wb_object~get_object( ) ).
        ro_data = lo_ifc->get_interface_data( ).
      CATCH cx_root.
        CLEAR ro_data.
    ENDTRY.
  ENDMETHOD.

  METHOD sfp_trim_code.
*   Die Code-Tabellen einer Schnittstelle (Typen, Initialisierung,
*   Routinen) enthalten viele leere Nachlaufzeilen. Fuehrende und innere
*   Leerzeilen bleiben erhalten, die am Ende werden entfernt, damit im
*   Dokument keine grossen Luecken stehen.
    DATA lt TYPE string_table.
    LOOP AT it_code INTO DATA(lv_l).
      APPEND lv_l TO lt.
    ENDLOOP.
    WHILE lines( lt ) > 0.
      DATA(lv_idx)  = lines( lt ).
      DATA(lv_last) = condense( lt[ lv_idx ] ).
      IF lv_last IS INITIAL.
        DELETE lt INDEX lv_idx.
      ELSE.
        EXIT.
      ENDIF.
    ENDWHILE.
    rt_lines = lt.
  ENDMETHOD.

  METHOD sfpi_source.
*   Aus einer Adobe-Form-Schnittstelle wird der lesbare Quelltext
*   zusammengetragen: globale Typen, Initialisierungscoding und
*   Formularroutinen. Jeder Block wird nur ausgegeben, wenn er nach dem
*   Entfernen der Nachlaufleerzeilen noch Inhalt hat.
    DATA(lo_data) = sfpi_ifc_data( iv_name ).
    IF lo_data IS NOT BOUND.
      RETURN.
    ENDIF.

    DATA lt_src TYPE string_table.

    DATA(lo_gd)  = lo_data->get_global_definitions( ).
    DATA(lt_typ) = sfp_trim_code( lo_gd->get_types( ) ).
    IF lt_typ IS NOT INITIAL.
      APPEND |*--- { lcl_t=>t( d = 'Globale Typen' e = 'Global types' ) } ---| TO lt_src.
      APPEND LINES OF lt_typ TO lt_src.
      APPEND `` TO lt_src.
    ENDIF.

    DATA(lo_code) = lo_data->get_coding( ).
    DATA(lt_ini)  = sfp_trim_code( lo_code->get_init_coding( ) ).
    IF lt_ini IS NOT INITIAL.
      APPEND |*--- { lcl_t=>t( d = 'Initialisierung' e = 'Initialization' ) } ---| TO lt_src.
      APPEND LINES OF lt_ini TO lt_src.
      APPEND `` TO lt_src.
    ENDIF.

    DATA(lt_frm) = sfp_trim_code( lo_code->get_forms_coding( ) ).
    IF lt_frm IS NOT INITIAL.
      APPEND |*--- { lcl_t=>t( d = 'Formularroutinen' e = 'Form routines' ) } ---| TO lt_src.
      APPEND LINES OF lt_frm TO lt_src.
      APPEND `` TO lt_src.
    ENDIF.

    rt_source = lt_src.
  ENDMETHOD.

  METHOD sfpf_node_label.
*   Die numerischen Knotentypen des Kontextbaums (IF_FP_NODE=>C_TYPE_*),
*   lesbar gemacht.
    CASE iv_type.
      WHEN 1.  rv_label = lcl_t=>t( d = 'Kontext'                   e = 'Context' ).
      WHEN 2.  rv_label = lcl_t=>t( d = 'Feld'                      e = 'Field' ).
      WHEN 3.  rv_label = lcl_t=>t( d = 'Struktur'                  e = 'Structure' ).
      WHEN 4.  rv_label = lcl_t=>t( d = 'Ordner'                    e = 'Folder' ).
      WHEN 5.  rv_label = lcl_t=>t( d = 'Textbaustein'              e = 'Text module' ).
      WHEN 6.  rv_label = lcl_t=>t( d = 'Text-Include'              e = 'Text include' ).
      WHEN 7.  rv_label = lcl_t=>t( d = 'Dynamischer Text'          e = 'Dynamic text' ).
      WHEN 8.  rv_label = lcl_t=>t( d = 'BTF-Text'                  e = 'BTF text' ).
      WHEN 9.  rv_label = lcl_t=>t( d = 'Adresse'                   e = 'Address' ).
      WHEN 10. rv_label = lcl_t=>t( d = 'Grafik (URL)'             e = 'Graphic (URL)' ).
      WHEN 11. rv_label = lcl_t=>t( d = 'Grafik (Inhalt)'          e = 'Graphic (content)' ).
      WHEN 12. rv_label = lcl_t=>t( d = 'Schleife'                  e = 'Loop' ).
      WHEN 13. rv_label = lcl_t=>t( d = 'Schleifendaten'            e = 'Loop data' ).
      WHEN 14. rv_label = lcl_t=>t( d = 'Alternative'               e = 'Alternative' ).
      WHEN 15. rv_label = lcl_t=>t( d = 'Alternative (wahr)'        e = 'Alternative (true)' ).
      WHEN 16. rv_label = lcl_t=>t( d = 'Alternative (falsch)'      e = 'Alternative (false)' ).
      WHEN 17. rv_label = lcl_t=>t( d = 'Programmzeilen'            e = 'Program lines' ).
      WHEN 18. rv_label = lcl_t=>t( d = 'Kommando'                  e = 'Command' ).
      WHEN 19. rv_label = lcl_t=>t( d = 'Einzelsatz'                e = 'Single record' ).
      WHEN 20. rv_label = lcl_t=>t( d = 'Schleifensteuerung (Daten)'  e = 'Loop control (data)' ).
      WHEN 21. rv_label = lcl_t=>t( d = 'Schleifensteuerung (Gruppe)' e = 'Loop control (group)' ).
      WHEN OTHERS. rv_label = |{ lcl_t=>t( d = 'Typ' e = 'Type' ) } { iv_type }|.
    ENDCASE.
  ENDMETHOD.

  METHOD sfpf_context.
*   Ein Kontextknoten und darunter, rekursiv, seine Kinder. Anders als beim
*   Smart Form gibt es keine Geschwisterliste - Kinder haengen ueber
*   GET_CHILD (erstes Kind) und GET_SUCCESSOR (naechstes Geschwister)
*   aneinander. Die Gliederungsnummer bildet die Hierarchie ohne
*   Einrueckung ab, damit sie in jedem Ausgabeformat erhalten bleibt.
    IF io_node IS NOT BOUND.
      RETURN.
    ENDIF.

    DATA lv_desc TYPE fptext.
    TRY.
        lv_desc = io_node->get_description( ).
      CATCH cx_fp_api_usage.
    ENDTRY.

    DATA(lv_type) = sfpf_node_label( io_node->get_type( ) ).
    DATA(lv_name) = CONV string( io_node->get_name( ) ).
    DATA(lv_disp) = COND string( WHEN lv_name IS NOT INITIAL THEN lv_name ELSE lv_type ).
    DATA(lv_roll) = COND string( WHEN lv_desc IS NOT INITIAL THEN |{ lv_type }: { lv_desc }|
                                 ELSE lv_type ).

    APPEND VALUE ty_field(
      name     = condense( |{ iv_outline }  { lv_disp }| )
      rollname = lv_roll ) TO ct_field.

    DATA lv_i   TYPE i.
    DATA(lo_ch) = io_node->get_child( ).
    WHILE lo_ch IS BOUND.
      lv_i = lv_i + 1.
      DATA(lv_sub) = COND string( WHEN iv_outline IS INITIAL THEN |{ lv_i }|
                                  ELSE |{ iv_outline }.{ lv_i }| ).
      sfpf_context( EXPORTING io_node = lo_ch iv_outline = lv_sub
                    CHANGING  ct_field = ct_field ).
      lo_ch = lo_ch->get_successor( ).
    ENDWHILE.
  ENDMETHOD.

  METHOD sfp_param_rows.
*   Haengt die Parameter einer Richtung an ein Schnittstellen-Objekt.
    DATA lv_dir TYPE string.
    CASE iv_dir.
      WHEN 'I'. lv_dir = lcl_t=>t( d = 'Import'   e = 'Import' ).
      WHEN 'E'. lv_dir = lcl_t=>t( d = 'Export'   e = 'Export' ).
      WHEN 'T'. lv_dir = lcl_t=>t( d = 'Tabelle'  e = 'Table' ).
      WHEN 'X'. lv_dir = lcl_t=>t( d = 'Ausnahme' e = 'Exception' ).
      WHEN OTHERS. lv_dir = iv_dir.
    ENDCASE.

    LOOP AT it_par INTO DATA(ls_par).
      IF ls_par-standard = 'X'.
        CONTINUE.
      ENDIF.
      DATA(lv_def) = condense( |{ ls_par-typing } { ls_par-typename }| ).
      DATA(lv_rn)  = COND string( WHEN lv_def IS NOT INITIAL THEN |{ lv_dir }: { lv_def }|
                                  ELSE lv_dir ).
      IF ls_par-optional = 'X'.
        lv_rn = |{ lv_rn } ({ lcl_t=>t( d = 'optional' e = 'optional' ) })|.
      ENDIF.
      io_obj->add_field( VALUE ty_field( name     = CONV string( ls_par-name )
                                         rollname = lv_rn ) ).
    ENDLOOP.
  ENDMETHOD.

  METHOD add_sfp_ifc_blocks.
*   Schnittstelle und globale Definitionen einer Adobe-Form-Schnittstelle.
*   Wird sowohl fuer die Schnittstelle selbst (SFPI) als auch fuer das
*   Formular (SFPF, ueber seinen Schnittstellennamen) verwendet.
    DATA(lo_data) = sfpi_ifc_data( iv_ifname ).
    IF lo_data IS NOT BOUND.
      RETURN.
    ENDIF.

*   Formularschnittstelle: Import-/Export-/Tabellenparameter und Ausnahmen.
    DATA(lo_par) = lo_data->get_parameters( ).
    DATA(lo_ifc) = NEW lcl_object( iv_type = CONV string( iv_type )
                                   iv_name = CONV string( iv_name ) ).
    lo_ifc->set_note( |{ lcl_t=>t( d = 'Formularschnittstelle' e = 'Form interface' ) } ({ iv_ifname })| ).
    sfp_param_rows( io_obj = lo_ifc it_par = lo_par->get_import_parameters( ) iv_dir = 'I' ).
    sfp_param_rows( io_obj = lo_ifc it_par = lo_par->get_export_parameters( ) iv_dir = 'E' ).
    sfp_param_rows( io_obj = lo_ifc it_par = lo_par->get_table_parameters( )  iv_dir = 'T' ).
    sfp_param_rows( io_obj = lo_ifc it_par = lo_par->get_exceptions( )        iv_dir = 'X' ).
    IF lo_ifc->get_fields( ) IS NOT INITIAL.
      io_chapter->add_object( lo_ifc ).
    ENDIF.

*   Globale Definitionen: global vereinbarte Datenfelder und Feldsymbole.
    DATA(lo_gd)    = lo_data->get_global_definitions( ).
    DATA(lt_gdata) = lo_gd->get_global_data( ).
    DATA(lt_fsym)  = lo_gd->get_fieldsymbols( ).
    IF lt_gdata IS NOT INITIAL OR lt_fsym IS NOT INITIAL.
      DATA(lo_gbl) = NEW lcl_object( iv_type = CONV string( iv_type )
                                     iv_name = CONV string( iv_name ) ).
      lo_gbl->set_note( lcl_t=>t( d = 'Globale Definitionen' e = 'Global definitions' ) ).
      LOOP AT lt_gdata INTO DATA(ls_gd).
        DATA(lv_gdef) = condense( |{ ls_gd-typing } { ls_gd-typename }| ).
        IF ls_gd-constant = 'X'.
          lv_gdef = condense( |{ lv_gdef } ({ lcl_t=>t( d = 'Konstante' e = 'constant' ) })| ).
        ENDIF.
        lo_gbl->add_field( VALUE ty_field( name     = CONV string( ls_gd-name )
                                           rollname = lv_gdef ) ).
      ENDLOOP.
      LOOP AT lt_fsym INTO DATA(ls_fs).
        DATA(lv_fdef) = condense( |{ lcl_t=>t( d = 'Feldsymbol' e = 'Field symbol' ) } | &&
                                  |{ ls_fs-typing } { ls_fs-typename }| ).
        lo_gbl->add_field( VALUE ty_field( name     = CONV string( ls_fs-name )
                                           rollname = lv_fdef ) ).
      ENDLOOP.
      io_chapter->add_object( lo_gbl ).
    ENDIF.
  ENDMETHOD.

  METHOD read_source.

    DATA(lt_src) = source_lines( iv_type = iv_type iv_name = iv_name ).
    IF lt_src IS INITIAL.
      RETURN.
    ENDIF.

    DATA lv_n TYPE i.
    LOOP AT lt_src INTO DATA(lv_line).
      lv_n = lv_n + 1.
      IF mv_maxsrc > 0 AND lv_n > mv_maxsrc.
        rv_source = |{ rv_source }{ cl_abap_char_utilities=>newline }| &&
                    |* ... { lcl_t=>t( d = `gekürzt bei` e = `truncated at` ) }| &&
                    | { mv_maxsrc } { lcl_t=>t( d = `von` e = `of` ) }| &&
                    | { lines( lt_src ) }|.
*       Mindestens ein Quelltext ist an der Zeilengrenze abgeschnitten.
*       Das gehoert in den Kopf, sonst meldet er Vollstaendigkeit, die
*       nicht besteht.
        mv_src_trunc = abap_true.
        EXIT.
      ENDIF.
      IF rv_source IS INITIAL.
        rv_source = lv_line.
      ELSE.
        rv_source = |{ rv_source }{ cl_abap_char_utilities=>newline }{ lv_line }|.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD func_include.
*   The include of a function module is L<group>U<number>; TFDIR holds the
*   frame program and the number.
    SELECT SINGLE pname, include FROM tfdir
      WHERE funcname = @iv_func
      INTO @DATA(ls_fd).
    IF sy-subrc <> 0 OR ls_fd-pname IS INITIAL.
      RETURN.
    ENDIF.
    rv_include = |L{ ls_fd-pname+4 }U{ ls_fd-include }|.
  ENDMETHOD.

  METHOD func_group.
    SELECT SINGLE pname FROM tfdir
      WHERE funcname = @iv_func
      INTO @DATA(lv_pname).
    IF sy-subrc = 0 AND lv_pname IS NOT INITIAL.
      rv_group = lv_pname+4.
    ENDIF.
  ENDMETHOD.

  METHOD cross_prefix.
*   WBCROSSGT records references under the include they appear in, not
*   under the object name. For most types the include starts with the
*   object name; a function module and a function group are the exceptions.
    CASE iv_type.
      WHEN 'FUNC'.
        rv_prefix = func_include( CONV rs38l_fnam( iv_name ) ).
      WHEN 'FUGR'.
        rv_prefix = |L{ iv_name }|.
      WHEN OTHERS.
        rv_prefix = iv_name.
    ENDCASE.
  ENDMETHOD.

  METHOD add_calls.

    " Outgoing references - the counterpart to the where-used list. Neither
    " CROSS nor WBCROSSGT carries a secondary index for this direction, so
    " the read is a scan. On HANA that is acceptable for a column store, but
    " it is the reason this option is switched off by default.

    TYPES: BEGIN OF ty_call,
             rank  TYPE i,
             what  TYPE string,
             kind  TYPE string,
             otype TYPE trobjtype,
           END OF ty_call.

    DATA lt_call TYPE STANDARD TABLE OF ty_call.
    DATA ls_call TYPE ty_call.
    DATA lv_max  TYPE i.

    lv_max = mv_maxuse.
    IF lv_max <= 0.
      lv_max = 100000.
    ENDIF.

*   What the source says. It leads the list: a call and a table access are
*   what the reader looks for first, and neither is reliably indexed.
    LOOP AT scan_source_calls( iv_type = iv_type iv_name = iv_name )
         INTO DATA(ls_sc).
      CLEAR ls_call.
      CASE ls_sc-type.
        WHEN 'FUNC' OR 'PROG'. ls_call-rank = 0.
        WHEN 'TABL' OR 'VIEW'. ls_call-rank = 1.
        WHEN OTHERS.           ls_call-rank = 3.
      ENDCASE.
      ls_call-what  = ls_sc-name.
      ls_call-kind  = ls_sc-kind.
      ls_call-otype = ls_sc-type.
      APPEND ls_call TO lt_call.
    ENDLOOP.

    DATA lv_prog TYPE cross-prog.
    lv_prog = cross_prefix( iv_type = iv_type iv_name = iv_name ).
    SELECT name, type FROM cross
      WHERE prog = @lv_prog
      INTO TABLE @DATA(lt_cr)
      UP TO @lv_max ROWS.

    LOOP AT lt_cr INTO DATA(ls_cr).
      CLEAR ls_call.
      ls_call-rank = 4.
      ls_call-what = ls_cr-name.
      ls_call-kind = |{ lcl_t=>t( d = `Verweis` e = `reference` ) } { ls_cr-type }|.
      APPEND ls_call TO lt_call.
    ENDLOOP.

    " The includes of an object all start with its name, so a prefix match
    " yields what it consumes. Three record types are relevant and they say
    " different things: ME are the calls, TY the global types, DA the
    " constants and attributes.
    "
    " CROSS above is empty in many S/4 systems because the classic index is
    " not built there (SAPRSEUB); WBCROSSGT then carries everything.
    "
    " Each record type is read with its own limit. A single select with a
    " shared limit would return an arbitrary slice, and with a few hundred
    " types per program the calls would regularly fall out of it.
    DATA lv_like TYPE string.
    DATA lt_gt   TYPE STANDARD TABLE OF wbcrossgt.
    DATA lt_one  TYPE STANDARD TABLE OF wbcrossgt.
    DATA lv_ot   TYPE wbcrossgt-otype.

    lv_like = |{ cross_prefix( iv_type = iv_type iv_name = iv_name ) }%|.
    LOOP AT VALUE string_table( ( `ME` ) ( `TY` ) ( `DA` ) ) INTO DATA(lv_type).
      lv_ot = lv_type.
      SELECT * FROM wbcrossgt
        WHERE otype = @lv_ot AND include LIKE @lv_like
        INTO TABLE @lt_one
        UP TO @lv_max ROWS.
      APPEND LINES OF lt_one TO lt_gt.
    ENDLOOP.

    LOOP AT lt_gt INTO DATA(ls_gt).

      " Named actual parameters are stored as DA below their method and add
      " nothing but noise - the method itself is already in the list.
      IF ls_gt-otype = 'DA' AND ls_gt-name CS '\ME:'.
        CONTINUE.
      ENDIF.

      CLEAR ls_call.
      ls_call-what = ls_gt-name.
      CASE ls_gt-otype.
        WHEN 'ME'.
          ls_call-rank = 1.
          ls_call-kind = lcl_t=>t( d = 'Methodenaufruf' e = 'method call' ).
        WHEN 'TY'.
          ls_call-rank = 2.
          ls_call-kind = lcl_t=>t( d = 'Typverwendung' e = 'type used' ).
        WHEN 'DA'.
          ls_call-rank = 3.
          ls_call-kind = lcl_t=>t( d = 'Datenobjekt' e = 'data object' ).
      ENDCASE.
      APPEND ls_call TO lt_call.

    ENDLOOP.

    DELETE lt_call WHERE what = iv_name OR what IS INITIAL.
    IF lt_call IS INITIAL.
      RETURN.
    ENDIF.

    SORT lt_call BY what rank.
    DELETE ADJACENT DUPLICATES FROM lt_call COMPARING what.

*   Without the SAP standard the list shows what the developer wrote and
*   not the kernel of the system around it. The base name decides - a
*   method call carries its class in front of the backslash.
    IF mv_nosap = abap_true AND lt_call IS NOT INITIAL.
      DATA lt_cref TYPE ty_objrefs.
      LOOP AT lt_call INTO ls_call.
        APPEND VALUE #( type = ls_call-otype
                        name = base_name( ls_call-what ) ) TO lt_cref.
      ENDLOOP.
      drop_sap( CHANGING ct_ref = lt_cref ).
      SORT lt_cref BY name.
      DATA lt_keep TYPE STANDARD TABLE OF ty_call.
      LOOP AT lt_call INTO ls_call.
        READ TABLE lt_cref TRANSPORTING NO FIELDS
             WITH KEY name = base_name( ls_call-what ) BINARY SEARCH.
        IF sy-subrc = 0.
          APPEND ls_call TO lt_keep.
        ENDIF.
      ENDLOOP.
      lt_call = lt_keep.
      IF lt_call IS INITIAL.
        RETURN.
      ENDIF.
    ENDIF.

    " Order by kind: if the limit cuts, the calls should survive and not a
    " random slice of the type list.
    SORT lt_call BY rank what.

    DATA(lo_c) = NEW lcl_object( iv_type = 'CALLS'
                                 iv_name = CONV string( iv_name ) ).

    DATA(lv_total) = lines( lt_call ).
    IF mv_maxuse > 0 AND lv_total > mv_maxuse.
      DELETE lt_call FROM mv_maxuse + 1.
      lo_c->set_note( |{ lcl_t=>t( d = `Verwendete Objekte` e = `Objects used` ) }| &&
                      | { lcl_t=>t( d = `(gekürzt bei` e = `(truncated at` ) }| &&
                      | { mv_maxuse } { lcl_t=>t( d = `von` e = `of` ) } { lv_total })| ).
      lo_c->set_truncated( abap_true ).
    ELSE.
      lo_c->set_note( lcl_t=>t( d = 'Verwendete Objekte' e = 'Objects used' ) ).
    ENDIF.
    lo_c->set_row_count( lv_total ).

    LOOP AT lt_call INTO ls_call.
      lo_c->add_field( VALUE ty_field( name     = ls_call-what
                                       rollname = ls_call-kind ) ).
    ENDLOOP.

    io_chapter->add_object( lo_c ).
    mv_n_call = mv_n_call + 1.

  ENDMETHOD.

  METHOD pack_reason.
    " The exceptions of the package API in plain text. A bare number in the
    " document would otherwise send the reader into the function library.
    CASE iv_subrc.
      WHEN 1. rv_reason = lcl_t=>t( d = 'kein Paket angegeben'
                                    e = 'no package specified' ).
      WHEN 2. rv_reason = lcl_t=>t( d = 'Paket ohne Katalogeintrag in TDEVC'
                                    e = 'package has no TDEVC record' ).
      WHEN 3. rv_reason = lcl_t=>t( d = 'Paket ohne Eintrag in TADIR'
                                    e = 'package has no TADIR record' ).
      WHEN 4. rv_reason = lcl_t=>t( d = 'Paket existiert nicht - Name pruefen'
                                    e = 'package does not exist - check the name' ).
      WHEN 5. rv_reason = lcl_t=>t( d = 'ungueltiges Oberpaket'
                                    e = 'invalid superpackage' ).
      WHEN 6. rv_reason = lcl_t=>t( d = 'kein Ausgabeparameter angefordert'
                                    e = 'no output parameter requested' ).
      WHEN OTHERS. rv_reason = |{ lcl_t=>t( d = `unbekannte Ursache`
                                            e = `unknown reason` ) } { iv_subrc }|.
    ENDCASE.
  ENDMETHOD.

  METHOD add_usages.

    " The where-used list comes from the cross-reference tables of the
    " workbench. WBCROSSGT records the use of global types - classes,
    " interfaces and DDIC types among them -, CROSS the remaining
    " references on program level. Both are merged.
    "
    " The list can grow very large: a heavily used table easily has
    " thousands of consumers. Hence the separate limit, and a note in the
    " document whenever it takes effect.

    TYPES: BEGIN OF ty_use,
             where TYPE string,
             kind  TYPE string,
*            A view or a CDS view is a repository object, not an include.
*            It has no source to scan and no frame program behind it.
             ddic  TYPE abap_bool,
             cls   TYPE c LENGTH 4,
*            Die Felder, die diese Stelle anfasst. WBCROSSGT fuehrt eine
*            Feldverwendung unter <Struktur>\TY:<Feld>; der Name allein
*            findet sie nicht.
             flds  TYPE string,
           END OF ty_use.
    DATA lt_use TYPE STANDARD TABLE OF ty_use.
    DATA ls_use TYPE ty_use.
    DATA lv_max TYPE i.
*   Hat eine der Abfragen an ihrer Zeilengrenze abgeschnitten? Dann ist
*   die Liste unvollstaendig, und das gehoert ins Dokument.
    DATA lv_cut TYPE abap_bool.

    lv_max = mv_maxuse.
    IF lv_max <= 0.
      lv_max = 100000.
    ENDIF.

*   Erst die Werkbank fragen. Sie kennt Stellen, die in keiner der
*   Indextabellen stehen - allen voran DDL Sources. Ein CDS mit
*   klassischem SQL-View steht in DD26S nur unter dem Namen dieses Views,
*   eine CDS View Entity gar nicht.
    crossref_users( EXPORTING iv_type = iv_type
                              iv_name = iv_name
                    IMPORTING et_hit  = DATA(lt_cru)
                              ev_ok   = DATA(lv_cr_ok) ).

    IF lv_cr_ok = abap_true.

      IF lines( lt_cru ) > lv_max.
        DELETE lt_cru FROM lv_max + 1.
      ENDIF.
      LOOP AT lt_cru INTO DATA(ls_cru).
        CLEAR ls_use.
        ls_use-where = ls_cru-name.
        ls_use-cls   = ls_cru-type.
        ls_use-kind  = lcl_t=>t( d = 'Verwendung' e = 'usage' ).
        APPEND ls_use TO lt_use.
      ENDLOOP.

    ELSE.

      DATA lv_name120 TYPE wbcrossgt-name.
      lv_name120 = iv_name.

      SELECT include FROM wbcrossgt
        WHERE otype = 'TY' AND name = @lv_name120
        INTO TABLE @DATA(lt_gt)
        UP TO @lv_max ROWS.

      LOOP AT lt_gt INTO DATA(ls_gt).
        CLEAR ls_use.
        ls_use-where = ls_gt-include.
        ls_use-kind  = lcl_t=>t( d = 'Typverwendung' e = 'Type usage' ).
        APPEND ls_use TO lt_use.
      ENDLOOP.

      DATA lv_name_cr TYPE cross-name.
      lv_name_cr = iv_name.

      SELECT prog FROM cross
        WHERE name = @lv_name_cr
        INTO TABLE @DATA(lt_cr)
        UP TO @lv_max ROWS.

      LOOP AT lt_cr INTO DATA(ls_cr).
        CLEAR ls_use.
        ls_use-where = ls_cr-prog.
        ls_use-kind  = lcl_t=>t( d = 'Programmverwendung' e = 'Program usage' ).
        APPEND ls_use TO lt_use.
      ENDLOOP.

    ENDIF.

*   Feldverwendungen. WBCROSSGT fuehrt sie unter <Struktur>\TY:<Feld> -
*   die Suche nach dem blossen Strukturnamen findet keine einzige davon.
*   Das ist die Liste, die SE11 unter "Verwendungsnachweis Strukturfeld"
*   zeigt, und bei einem IDoc-Segment oft die einzige, die es gibt: das
*   Segment als Ganzes wird selten typisiert, seine Felder dauernd
*   gelesen.
*
*   Der Unterstrich ist im LIKE ein Platzhalter fuer ein Zeichen. Ein
*   Strukturname wie ZBLE_MBXSH wuerde ohne Maskierung auch ZBLEXMBXSH
*   treffen, deshalb die Fluchtsequenz.
    DATA lv_fpat TYPE wbcrossgt-name.
    DATA lv_fesc TYPE string.

    lv_fesc = iv_name.
    REPLACE ALL OCCURRENCES OF `#` IN lv_fesc WITH `##`.
    REPLACE ALL OCCURRENCES OF `_` IN lv_fesc WITH `#_`.
    REPLACE ALL OCCURRENCES OF `%` IN lv_fesc WITH `#%`.
    lv_fpat = lv_fesc && '\TY:%'.

    SELECT name, include FROM wbcrossgt
      WHERE otype = 'TY' AND name LIKE @lv_fpat ESCAPE '#'
      INTO TABLE @DATA(lt_fu)
      UP TO @lv_max ROWS.

    IF lines( lt_fu ) >= lv_max.
      lv_cut = abap_true.
    ENDIF.

*   Angehaengt wird je Treffer eine Zeile; zusammengezogen wird weiter
*   unten in einem Durchlauf. Hier je Treffer die Liste zu durchsuchen
*   waere quadratisch, und bei einer viel benutzten Struktur sind das
*   schnell Millionen Vergleiche.
    LOOP AT lt_fu INTO DATA(ls_fu).

      DATA lv_fld TYPE string.
      SPLIT ls_fu-name AT ':' INTO DATA(lv_dummy) lv_fld.
      IF lv_fld IS INITIAL.
        CONTINUE.
      ENDIF.

      CLEAR ls_use.
      ls_use-where = ls_fu-include.
      ls_use-kind  = lcl_t=>t( d = 'Feldverwendung' e = 'Field usage' ).
      ls_use-flds  = lv_fld.
      APPEND ls_use TO lt_use.

    ENDLOOP.

*   A table is not only used in code. Views and CDS views are built on it,
*   and the cross-reference index does not know about either - the DDIC
*   does: DD26S names the base tables of a view, DDLDEPENDENCY the objects
*   a CDS view reads.
    IF iv_type = 'TABL' OR iv_type = 'VIEW'.

      DATA lv_tabname TYPE dd26s-tabname.
      lv_tabname = iv_name.
      SELECT DISTINCT viewname FROM dd26s
        WHERE tabname = @lv_tabname AND as4local = 'A'
        INTO TABLE @DATA(lt_vw)
        UP TO @lv_max ROWS.

*     Ein CDS mit klassischem SQL-View steht hier unter dem Namen dieses
*     Views - ZBWDICOMPANY2VH statt ZBWD_I_COMPANY2_VH. Fuer den Leser
*     zaehlt die DDL Source, und genau die zeigt auch SE11. DDLDEPENDENCY
*     bildet SQL-View auf DDL Source ab.
      DATA lt_vn TYPE STANDARD TABLE OF ddldependency-objectname.
      LOOP AT lt_vw INTO DATA(ls_vw).
        APPEND ls_vw-viewname TO lt_vn.
      ENDLOOP.
      IF lt_vn IS NOT INITIAL.
        SELECT ddlname, objectname FROM ddldependency
          FOR ALL ENTRIES IN @lt_vn
          WHERE objectname = @lt_vn-table_line AND objecttype = 'VIEW'
          INTO TABLE @DATA(lt_ddl).
        SORT lt_ddl BY objectname.
      ENDIF.

      LOOP AT lt_vw INTO ls_vw.
        IF ls_vw-viewname = iv_name.
          CONTINUE.
        ENDIF.
        CLEAR ls_use.
        READ TABLE lt_ddl INTO DATA(ls_ddl)
             WITH KEY objectname = ls_vw-viewname BINARY SEARCH.
        IF sy-subrc = 0 AND ls_ddl-ddlname IS NOT INITIAL.
          ls_use-where = ls_ddl-ddlname.
          ls_use-kind  = 'CDS View'.
        ELSE.
          ls_use-where = ls_vw-viewname.
          ls_use-kind  = lcl_t=>t( d = 'View' e = 'view' ).
        ENDIF.
        ls_use-ddic = abap_true.
        APPEND ls_use TO lt_use.
      ENDLOOP.

*     Eine CDS View Entity hat keinen SQL-View und steht deshalb in DD26S
*     nicht. Sie bleibt hier unsichtbar; siehe offene Punkte.
      DATA lv_objname TYPE ddldependency-objectname.
      lv_objname = iv_name.
      SELECT DISTINCT ddlname FROM ddldependency
        WHERE objectname = @lv_objname AND objecttype <> 'VIEW'
        INTO TABLE @DATA(lt_cds)
        UP TO @lv_max ROWS.
      LOOP AT lt_cds INTO DATA(ls_cds).
        IF ls_cds-ddlname = iv_name.
          CONTINUE.
        ENDIF.
        CLEAR ls_use.
        ls_use-where = ls_cds-ddlname.
        ls_use-kind  = 'CDS View'.
        ls_use-ddic  = abap_true.
        APPEND ls_use TO lt_use.
      ENDLOOP.

*     Hier wurde frueher entdoppelt. Das faellt weg: der Durchlauf
*     weiter unten tut dasselbe und nimmt dabei die Feldangaben mit -
*     ein DELETE ADJACENT DUPLICATES an dieser Stelle warf sie weg.

    ENDIF.

    IF lt_use IS INITIAL.
      RETURN.
    ENDIF.

    " CROSS keeps rows without a program name; they would show up as an
    " empty line in the document.
    DELETE lt_use WHERE where IS INITIAL.
    IF lt_use IS INITIAL.
      RETURN.
    ENDIF.

    SORT lt_use BY where kind.

*   Entdoppeln und dabei die Feldangaben zusammenziehen. Ein blosses
*   DELETE ADJACENT DUPLICATES wuerde die Zeile mit den Feldern
*   wegwerfen, wenn dieselbe Fundstelle auch ueber den Typ gefunden
*   wurde - und genau das ist der Normalfall.
    DATA lt_mrg TYPE STANDARD TABLE OF ty_use.
    DATA ls_cur TYPE ty_use.

    LOOP AT lt_use INTO ls_use.
      IF ls_cur-where <> ls_use-where.
        IF ls_cur-where IS NOT INITIAL.
          APPEND ls_cur TO lt_mrg.
        ENDIF.
        ls_cur = ls_use.
      ELSE.
        IF ls_cur-flds IS INITIAL.
          ls_cur-flds = ls_use-flds.
        ELSEIF ls_use-flds IS NOT INITIAL AND NOT ls_cur-flds CS ls_use-flds.
          ls_cur-flds = |{ ls_cur-flds }, { ls_use-flds }|.
        ENDIF.
*       Eine Fundstelle, die auch ueber den Typ kam, ist keine reine
*       Feldverwendung mehr.
        IF ls_cur-kind = lcl_t=>t( d = 'Feldverwendung' e = 'Field usage' )
           AND ls_use-kind <> ls_cur-kind.
          ls_cur-kind = ls_use-kind.
        ENDIF.
      ENDIF.
    ENDLOOP.
    IF ls_cur-where IS NOT INITIAL.
      APPEND ls_cur TO lt_mrg.
    ENDIF.
    lt_use = lt_mrg.

    DATA(lo_u) = NEW lcl_object( iv_type = 'USAGE'
                                 iv_name = CONV string( iv_name ) ).

    IF mv_maxuse > 0 AND ( lines( lt_use ) >= mv_maxuse OR lv_cut = abap_true ).
      lo_u->set_note( |{ lcl_t=>t( d = `Verwendungsnachweis` e = `Where-used list` ) }| &&
                      | { lcl_t=>t( d = `(gekürzt bei` e = `(truncated at` ) }| &&
                      | { mv_maxuse })| ).
      lo_u->set_truncated( abap_true ).
    ELSE.
      lo_u->set_note( lcl_t=>t( d = 'Verwendungsnachweis' e = 'Where-used list' ) ).
    ENDIF.
    lo_u->set_row_count( lines( lt_use ) ).

*   The index names the include, and an include says little on its own.
*   Behind it stands a report, a function group or a class pool - that is
*   what the reader recognises, and TRDIR-SUBC says which of the three.
    DATA lt_inc TYPE STANDARD TABLE OF progname.
    LOOP AT lt_use INTO ls_use WHERE ddic = abap_false.
      APPEND CONV progname( ls_use-where ) TO lt_inc.
    ENDLOOP.
    IF lt_inc IS INITIAL.
      APPEND INITIAL LINE TO lt_inc.
    ENDIF.
    SORT lt_inc BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_inc COMPARING table_line.

    SELECT include, master FROM d010inc
      FOR ALL ENTRIES IN @lt_inc
      WHERE include = @lt_inc-table_line
      INTO TABLE @DATA(lt_mast).
    SORT lt_mast BY include.

    DATA lt_prog TYPE STANDARD TABLE OF progname.
    LOOP AT lt_use INTO ls_use WHERE ddic = abap_false.
      APPEND main_program( CONV progname( ls_use-where ) ) TO lt_prog.
    ENDLOOP.
    IF lt_prog IS INITIAL.
      APPEND INITIAL LINE TO lt_prog.
    ENDIF.
    SORT lt_prog BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_prog COMPARING table_line.

    SELECT name, subc FROM trdir
      FOR ALL ENTRIES IN @lt_prog
      WHERE name = @lt_prog-table_line
      INTO TABLE @DATA(lt_dir).
    SORT lt_dir BY name.

*   Was TRDIR nicht kennt, ist kein Programm: eine Datendefinition, ein
*   View, eine Tabelle. Die Bezeichnung dafuer liefert die Werkbank
*   selbst - EUOBJT fuehrt zu jeder Objektklasse einen Text, sogar in der
*   Einzahl und sprachabhaengig. Das ist verlaesslicher als ein Blick in
*   TADIR: dort kollidieren Namen, ein View heisst genauso wie das dazu
*   erzeugte Customizing-Objekt, und der Katalog haette keinen Grund, das
*   eine dem anderen vorzuziehen.
    DATA lt_cls TYPE STANDARD TABLE OF euobjt-type.
    LOOP AT lt_use INTO ls_use WHERE cls IS NOT INITIAL.
      APPEND CONV euobjt-type( ls_use-cls ) TO lt_cls.
    ENDLOOP.
    SORT lt_cls BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_cls COMPARING table_line.

    DATA lt_clst TYPE STANDARD TABLE OF euobjt.
    IF lt_cls IS NOT INITIAL.
      SELECT * FROM euobjt
        FOR ALL ENTRIES IN @lt_cls
        WHERE spras = @mv_langu AND type = @lt_cls-table_line
        INTO TABLE @lt_clst.
      IF lt_clst IS INITIAL AND mv_falb = abap_true.
        SELECT * FROM euobjt
          FOR ALL ENTRIES IN @lt_cls
          WHERE spras = @mv_flang AND type = @lt_cls-table_line
          INTO TABLE @lt_clst.
      ENDIF.
      SORT lt_clst BY type.
    ENDIF.

*   How a table is used only shows in the source: the index knows that it
*   is used, not whether it is read or written. Done for the entry point
*   only, and the entry limit caps how many programs are read.
*   Scanned is the include the index points at, not its frame program. In a
*   function group the SELECT sits in LZ..U01 or LZ..F00, and SAPL<group>
*   holds nothing but the include list.
    TYPES: BEGIN OF ty_acc,
             prog TYPE progname,
             acc  TYPE string,
             hits TYPE ty_hits,
           END OF ty_acc.
    DATA lt_acc TYPE STANDARD TABLE OF ty_acc.
    DATA ls_a   TYPE ty_acc.

*   Only a table can be read or written; for everything else the pass just
*   collects the lines.
    DATA(lv_dml) = xsdbool( iv_type = 'TABL' OR iv_type = 'VIEW'
                            OR iv_type = 'DDLS' ).

    LOOP AT lt_inc INTO DATA(lv_pr).
      CLEAR ls_a.
      ls_a-prog = lv_pr.
      usage_scan( EXPORTING iv_prog   = lv_pr
                            iv_name   = iv_name
                            iv_access = lv_dml
                  IMPORTING ev_access = ls_a-acc
                            et_hits   = ls_a-hits ).
      APPEND ls_a TO lt_acc.
    ENDLOOP.
    SORT lt_acc BY prog.

    LOOP AT lt_use INTO ls_use.

      DATA lv_kind TYPE string.

*     A DDIC object stands for itself - no include, no frame program.
      IF ls_use-ddic = abap_true.
        lo_u->add_field( VALUE ty_field( name     = ls_use-where
                                         rollname = ls_use-kind ) ).
        CONTINUE.
      ENDIF.

      DATA(lv_main) = main_program( CONV progname( ls_use-where ) ).

      READ TABLE lt_dir INTO DATA(ls_dir)
           WITH KEY name = lv_main BINARY SEARCH.
      IF sy-subrc = 0.
        lv_kind = prog_kind( iv_subc = ls_dir-subc iv_prog = lv_main ).
*       For a function group the kind already carries the group name;
*       repeating SAPL<group> behind it says nothing new.
        IF ls_dir-subc <> 'F' AND lv_main <> ls_use-where.
          lv_kind = |{ lv_kind } { lv_main }|.
        ENDIF.
      ELSE.
        CLEAR lv_kind.
        IF ls_use-cls IS NOT INITIAL.
          READ TABLE lt_clst INTO DATA(ls_clst)
               WITH KEY type = ls_use-cls BINARY SEARCH.
          IF sy-subrc = 0.
            lv_kind = COND #( WHEN ls_clst-singular IS NOT INITIAL
                              THEN ls_clst-singular
                              ELSE ls_clst-stext ).
          ENDIF.
        ENDIF.
        IF lv_kind IS INITIAL.
          lv_kind = ls_use-kind.
        ENDIF.
      ENDIF.

      READ TABLE lt_acc INTO DATA(ls_acc)
           WITH KEY prog = ls_use-where BINARY SEARCH.
      IF sy-subrc = 0 AND ls_acc-acc IS NOT INITIAL.
        lv_kind = |{ lv_kind } - { ls_acc-acc }|.
      ENDIF.

*     Welche Felder diese Stelle anfasst. Ohne die Angabe steht in der
*     Liste nur, dass eine Klasse etwas mit der Struktur zu tun hat.
      IF ls_use-flds IS NOT INITIAL.
        lv_kind = |{ lv_kind } - { lcl_t=>t( d = `Felder` e = `fields` ) }| &&
                  | { ls_use-flds }|.
      ENDIF.

      lo_u->add_field( VALUE ty_field( name     = ls_use-where
                                       rollname = lv_kind ) ).
    ENDLOOP.

    io_chapter->add_object( lo_u ).
    mv_n_use = mv_n_use + 1.

*   The hit lines follow the list, one block per place of use. The list
*   answers "where", the block answers "how" - and that is the question
*   the reader has next.
    LOOP AT lt_use INTO ls_use WHERE ddic = abap_false.

      READ TABLE lt_acc INTO DATA(ls_h)
           WITH KEY prog = ls_use-where BINARY SEARCH.
      IF sy-subrc <> 0 OR ls_h-hits IS INITIAL.
        CONTINUE.
      ENDIF.

      DATA(lo_s) = NEW lcl_object( iv_type = 'SOURCE'
                                   iv_name = ls_use-where ).
      lo_s->set_note( |{ COND string(
          WHEN mv_fsrc = abap_true
          THEN lcl_t=>t( d = `Quelltext mit Fundstellen`
                         e = `Source with occurrences` )
          ELSE lcl_t=>t( d = `Fundstellen in` e = `Occurrences in` ) ) }| &&
                      | { ls_use-where }| ).
*     KEYFLAG marks the hit line. The field carries no key here - it is
*     the one flag the model already round-trips through the XML, and a
*     new attribute would break every document written so far.
*     Marked only in the full listing. In the pure hit list every line is
*     a hit, and marking all of them says nothing.
      LOOP AT ls_h-hits INTO DATA(ls_hit).
        lo_s->add_field( VALUE ty_field(
          name     = |{ ls_hit-line WIDTH = 6 ALIGN = RIGHT }|
          rollname = ls_hit-text
          keyflag  = COND #( WHEN mv_fsrc = abap_true THEN ls_hit-hit
                             ELSE abap_false ) ) ).
      ENDLOOP.
      io_chapter->add_object( lo_s ).

    ENDLOOP.

  ENDMETHOD.

  METHOD find_obj_cls.
*   Die Objektklasse, unter der die Werkbank ein Objekt sucht. Sie ist
*   nicht durchgaengig der TADIR-Typ: ein Funktionsbaustein heisst hier
*   FUNC, sein TADIR-Satz gehoert der Gruppe.
    CASE iv_type.
      WHEN 'TABL' OR 'VIEW' OR 'DTEL' OR 'DOMA' OR 'TTYP' OR 'SHLP'
        OR 'ENQU' OR 'PROG' OR 'CLAS' OR 'INTF' OR 'FUGR' OR 'MSAG'
        OR 'TRAN' OR 'DDLS'.
        rv_cls = iv_type.
      WHEN 'FUNC'.
        rv_cls = 'FUNC'.
      WHEN OTHERS.
        CLEAR rv_cls.
    ENDCASE.
  ENDMETHOD.

  METHOD crossref_users.
*   Der Verwendungsnachweis der Werkbank - derselbe Baustein, den SE11
*   ruft. Er kennt Quellen, die in keiner der Indextabellen stehen, allen
*   voran DDL Sources: ein CDS mit klassischem SQL-View taucht in DD26S
*   nur unter dem Namen dieses Views auf, eine CDS View Entity gar nicht.
*
*   Der Baustein arbeitet mit klassischen Ausnahmen und kann bei grossem
*   Umfang auf Batch ausweichen. Beides wird abgefangen; der Aufrufer
*   faellt dann auf die Indextabellen zurueck.
    CLEAR: et_hit, ev_ok.

    DATA(lv_cls) = find_obj_cls( iv_type ).
    IF lv_cls IS INITIAL.
      RETURN.
    ENDIF.

    DATA lt_find  TYPE STANDARD TABLE OF rsfind.
    DATA lt_found TYPE STANDARD TABLE OF rsfindlst.

    APPEND VALUE rsfind( object = iv_name ) TO lt_find.

    CALL FUNCTION 'RS_EU_CROSSREF'
      EXPORTING
        i_find_obj_cls           = lv_cls
        no_dialog                = 'X'
        without_text             = 'X'
      TABLES
        i_findstrings            = lt_find
        o_founds                 = lt_found
      EXCEPTIONS
        not_executed             = 1
        not_found                = 2
        illegal_object           = 3
        no_cross_for_this_object = 4
        batch                    = 5
        batchjob_error           = 6
        wrong_type               = 7
        object_not_exist         = 8
        OTHERS                   = 9.

*   NOT_FOUND und NO_CROSS_FOR_THIS_OBJECT sind Ergebnisse, keine Fehler:
*   das Objekt wird nirgends verwendet. Alles andere heisst, der Baustein
*   hat nicht geantwortet - dann greift der Rueckfall.
    CASE sy-subrc.
      WHEN 0.
        ev_ok = abap_true.
      WHEN 2 OR 4.
        ev_ok = abap_true.
        RETURN.
      WHEN OTHERS.
        RETURN.
    ENDCASE.

*   Zurueck kommen Namen mit der Objektklasse der Werkbank - DV, P, FF -
*   nicht mit dem TADIR-Typ, und Includes statt der Objekte dahinter.
*   Deshalb nur die Namen uebernehmen; die Einordnung macht der Aufrufer
*   mit derselben Aufloesung wie beim Rueckfall.
    LOOP AT lt_found INTO DATA(ls_f).
      IF ls_f-object IS NOT INITIAL.
        APPEND VALUE #( type = ls_f-object_cls
                        name = ls_f-object ) TO et_hit.
      ENDIF.
*     Das umschliessende Objekt hilft beim Aufloesen auf ein
*     Katalogobjekt, in der Trefferliste selbst waere es eine Dublette.
      IF iv_with_encl = abap_true AND ls_f-encl_objec IS NOT INITIAL.
        APPEND VALUE #( name = ls_f-encl_objec ) TO et_hit.
      ENDIF.
    ENDLOOP.

    SORT et_hit BY name type.
    DELETE ADJACENT DUPLICATES FROM et_hit COMPARING name.
  ENDMETHOD.

  METHOD usage_objects.
*   Die Objekte hinter einem Verwendungsnachweis, dokumentierbar gemacht.
*   Der Index nennt Includes; dokumentiert wird das Repository-Objekt
*   dahinter - der Report, die Funktionsgruppe, der Klassenpool.
*
*   Bewusst ohne Quelltext-Scan und ohne Fundstellen: hier zaehlt nur, wer
*   das Objekt verwendet, nicht wie. Das macht die Ausweitung bezahlbar.
*
    DATA lv_max TYPE i.
    lv_max = mv_maxuse.
    IF lv_max <= 0.
      lv_max = 1000.
    ENDIF.

    DATA lt_inc TYPE STANDARD TABLE OF progname.

*   Zuerst die Werkbank fragen, erst bei Fehlschlag die Indextabellen.
    crossref_users( EXPORTING iv_type      = iv_type
                              iv_name      = iv_name
                              iv_with_encl = abap_true
                    IMPORTING et_hit       = DATA(lt_cr_hit)
                              ev_ok        = DATA(lv_ok) ).

    IF lv_ok = abap_true.
      DATA lv_crp TYPE progname.
      LOOP AT lt_cr_hit INTO DATA(ls_crh).
        lv_crp = ls_crh-name.
        APPEND lv_crp TO lt_inc.
      ENDLOOP.
    ELSE.

      DATA lv_n120 TYPE wbcrossgt-name.
      lv_n120 = iv_name.
      SELECT include FROM wbcrossgt
        WHERE otype = 'TY' AND name = @lv_n120
        INTO TABLE @DATA(lt_g)
        UP TO @lv_max ROWS.
      LOOP AT lt_g INTO DATA(ls_g).
        APPEND ls_g-include TO lt_inc.
      ENDLOOP.

      DATA lv_ncr TYPE cross-name.
      lv_ncr = iv_name.
      SELECT prog FROM cross
        WHERE name = @lv_ncr
        INTO TABLE @DATA(lt_c)
        UP TO @lv_max ROWS.
      LOOP AT lt_c INTO DATA(ls_c).
        APPEND ls_c-prog TO lt_inc.
      ENDLOOP.

    ENDIF.

    DELETE lt_inc WHERE table_line IS INITIAL.
    SORT lt_inc BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_inc COMPARING table_line.

*   Die Werkbank kennt keine Mengengrenze; ein viel benutztes Datenelement
*   brachte sonst tausende Stellen mit.
    IF lines( lt_inc ) > lv_max.
      DELETE lt_inc FROM lv_max + 1.
    ENDIF.

*   Include auf sein Rahmenprogramm und dieses auf das Katalogobjekt.
    DATA lt_obj TYPE STANDARD TABLE OF sobj_name.
    LOOP AT lt_inc INTO DATA(lv_inc).
      DATA(lv_main) = main_program( lv_inc ).
      DATA lv_obj TYPE sobj_name.
      lv_obj = lv_main.
      IF strlen( lv_main ) > 4 AND lv_main(4) = 'SAPL'.
        lv_obj = lv_main+4.
      ELSEIF lv_main CS '='.
        SPLIT lv_main AT '=' INTO DATA(lv_head) DATA(lv_tail).
        lv_obj = lv_head.
      ENDIF.
      APPEND lv_obj TO lt_obj.
    ENDLOOP.

    IF iv_type = 'TABL' OR iv_type = 'VIEW'.
      DATA lv_tn TYPE dd26s-tabname.
      lv_tn = iv_name.
      SELECT DISTINCT viewname FROM dd26s
        WHERE tabname = @lv_tn AND as4local = 'A'
        INTO TABLE @DATA(lt_v)
        UP TO @lv_max ROWS.
      LOOP AT lt_v INTO DATA(ls_v).
        APPEND ls_v-viewname TO lt_obj.
      ENDLOOP.
    ENDIF.

    DELETE lt_obj WHERE table_line IS INITIAL OR table_line = iv_name.
    SORT lt_obj BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_obj COMPARING table_line.
    IF lt_obj IS INITIAL.
      RETURN.
    ENDIF.

    SELECT object, obj_name FROM tadir
      FOR ALL ENTRIES IN @lt_obj
      WHERE pgmid = 'R3TR' AND delflag = @abap_false
        AND object IN ( 'PROG', 'FUGR', 'CLAS', 'INTF', 'TABL', 'VIEW',
                        'DDLS', 'MSAG' )
        AND obj_name = @lt_obj-table_line
      INTO TABLE @DATA(lt_cat).

    LOOP AT lt_cat INTO DATA(ls_cat).
      APPEND VALUE #( type = ls_cat-object
                      name = ls_cat-obj_name ) TO rt_obj.
    ENDLOOP.

    SORT rt_obj BY type name.
    DELETE ADJACENT DUPLICATES FROM rt_obj COMPARING type name.
    drop_sap( CHANGING ct_ref = rt_obj ).
  ENDMETHOD.

  METHOD main_program.
*   The include belongs to a frame program - but not always to exactly
*   one. A shared include is listed in D010INC under every program that
*   includes it, and naming one of them would be a guess presented as a
*   fact. Only an unambiguous frame program is reported; otherwise the
*   include stands for itself.
    rv_prog = iv_include.

    SELECT DISTINCT master FROM d010inc
      WHERE include = @iv_include AND master <> @iv_include
      INTO TABLE @DATA(lt_master)
      UP TO 2 ROWS.

    IF lines( lt_master ) = 1.
      READ TABLE lt_master INTO DATA(ls_master) INDEX 1.
      IF ls_master-master IS NOT INITIAL.
        rv_prog = ls_master-master.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD prog_kind.
*   TRDIR-SUBC says what kind of program it is. The name of a function
*   group is more telling than its frame program SAPL<group>.
    CASE iv_subc.
      WHEN '1'. rv_kind = lcl_t=>t( d = 'Report' e = 'report' ).
      WHEN 'F'.
        rv_kind = lcl_t=>t( d = 'Funktionsgruppe' e = 'function group' ).
        IF strlen( iv_prog ) > 4 AND iv_prog(4) = 'SAPL'.
          rv_kind = |{ rv_kind } { iv_prog+4 }|.
        ENDIF.
      WHEN 'K'. rv_kind = lcl_t=>t( d = 'Klassenpool' e = 'class pool' ).
      WHEN 'J'. rv_kind = lcl_t=>t( d = 'Interfacepool' e = 'interface pool' ).
      WHEN 'M'. rv_kind = lcl_t=>t( d = 'Modulpool' e = 'module pool' ).
      WHEN 'S'. rv_kind = lcl_t=>t( d = 'Unterprogrammpool' e = 'subroutine pool' ).
      WHEN 'I'. rv_kind = 'Include'.
      WHEN 'T'. rv_kind = lcl_t=>t( d = 'Typgruppe' e = 'type pool' ).
      WHEN OTHERS. rv_kind = lcl_t=>t( d = 'Programm' e = 'program' ).
    ENDCASE.
  ENDMETHOD.

  METHOD usage_scan.
*   One pass over the source of a using include. It answers two questions
*   at once, so the source is read only once: how the object is accessed,
*   and in which lines it appears. The second is what the reader wants -
*   the same "Fundstellen" panel SE11 shows next to its hit list.
    CLEAR: ev_access, et_hits.

    DATA(lt_src) = source_lines( iv_type = 'PROG' iv_name = iv_prog ).
    IF lt_src IS INITIAL.
      RETURN.
    ENDIF.

    DATA lv_read  TYPE abap_bool.
    DATA lv_write TYPE abap_bool.
    DATA lv_up    TYPE string.
    DATA lv_no    TYPE i.
    DATA lv_cnt   TYPE i.
    DATA(lv_tab)  = to_upper( CONV string( iv_name ) ).

*   With the full-source option the whole listing is kept and capped by
*   the source limit; otherwise only the hits, capped by their own limit.
    DATA(lv_cap) = COND i( WHEN mv_fsrc = abap_true THEN mv_maxsrc
                           ELSE mv_maxhit ).

    LOOP AT lt_src INTO DATA(lv_line).

      lv_no = sy-tabix.
      lv_up = to_upper( lv_line ).
      SHIFT lv_up LEFT DELETING LEADING space.

      DATA lv_ishit TYPE abap_bool.
      CLEAR lv_ishit.

      IF lv_up IS NOT INITIAL AND lv_up(1) <> '*'.
        DATA(lv_code) = lv_up.
        IF lv_code CS '"'.
          SPLIT lv_code AT '"' INTO lv_code DATA(lv_rest).
        ENDIF.
*       Whole word only. Without the boundary ZSCANTEST would also match
*       ZSCANTEST_OLD.
        FIND FIRST OCCURRENCE OF REGEX |\\b{ lv_tab }\\b| IN lv_code ##REGEX_POSIX.
        IF sy-subrc = 0.
          lv_ishit = abap_true.
        ENDIF.
      ENDIF.

      IF lv_ishit = abap_false AND mv_fsrc = abap_false.
        CONTINUE.
      ENDIF.

      IF lv_cap <= 0 OR lv_cnt < lv_cap.
        lv_cnt = lv_cnt + 1.
        APPEND VALUE ty_hit( line = lv_no
                             hit  = lv_ishit
                             text = condense( val = lv_line
                                              del = cl_abap_char_utilities=>horizontal_tab ) )
               TO et_hits.
      ENDIF.

      IF iv_access = abap_false OR lv_ishit = abap_false.
        CONTINUE.
      ENDIF.
      lv_up = lv_code.

*     The write forms are checked first - DELETE FROM would otherwise be
*     counted as a read.
      FIND FIRST OCCURRENCE OF REGEX
        |^(?:INSERT\\s+(?:INTO\\s+)?\| \|UPDATE\\s+\| \|MODIFY\\s+\| \|DELETE\\s+(?:FROM\\s+)?)| &&
        |{ lv_tab }\\b|
        IN lv_up ##REGEX_POSIX.
      IF sy-subrc = 0.
        lv_write = abap_true.
        CONTINUE.
      ENDIF.

      FIND FIRST OCCURRENCE OF REGEX |\\b(?:FROM\|JOIN)\\s+{ lv_tab }\\b|
        IN lv_up ##REGEX_POSIX.
      IF sy-subrc = 0.
        lv_read = abap_true.
      ENDIF.

    ENDLOOP.

    IF lv_read = abap_true AND lv_write = abap_true.
      ev_access = lcl_t=>t( d = 'lesend und schreibend' e = 'read and written' ).
    ELSEIF lv_write = abap_true.
      ev_access = lcl_t=>t( d = 'schreibend' e = 'written' ).
    ELSEIF lv_read = abap_true.
      ev_access = lcl_t=>t( d = 'lesend' e = 'read' ).
    ENDIF.
  ENDMETHOD.

  METHOD add_details.

    DATA lv_tab TYPE dd03l-tabname.
    DATA lv_cls TYPE seocompo-clsname.

    CASE iv_type.

      WHEN 'TABL' OR 'VIEW'.
        lv_tab = iv_name.

*       Ein IDoc-Segment ist im Dictionary eine flache Zeichenstruktur:
*       DD03L fuehrt jedes Feld als CHAR ohne Datenelement. Das
*       Datenelement, das WE31 zeigt, steht allein in EDSAPPL, unter dem
*       Segmenttyp. Ohne diesen Umweg kaeme eine Feldliste heraus, in der
*       die Spalte Datenelement durchgaengig leer bleibt.
        DATA lt_f TYPE STANDARD TABLE OF ty_field WITH EMPTY KEY.
        DATA lv_seg TYPE edisegment-segtyp.

        CLEAR lt_f.
        lv_seg = iv_name.
        SELECT COUNT(*) FROM edisegment WHERE segtyp = @lv_seg.
        DATA(lv_is_seg) = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).

        IF lv_is_seg = abap_true.
          SELECT fieldname, rollname FROM edsappl
            WHERE segtyp = @lv_seg
            ORDER BY pos
            INTO TABLE @DATA(lt_sf).
          LOOP AT lt_sf INTO DATA(ls_sf).
            APPEND VALUE ty_field( name     = ls_sf-fieldname
                                   rollname = ls_sf-rollname ) TO lt_f.
          ENDLOOP.
        ENDIF.

*       Kein Segment, oder eines ohne Feldsaetze: der gewohnte Weg.
        IF lt_f IS INITIAL.
          SELECT fieldname, rollname, keyflag, datatype, leng FROM dd03l
            WHERE tabname = @lv_tab AND as4local = 'A' AND fieldname NOT LIKE '.%'
            ORDER BY position
            INTO TABLE @DATA(lt_d3).
          LOOP AT lt_d3 INTO DATA(ls_d3).
            DATA lv_ftype TYPE string.
            IF ls_d3-rollname IS NOT INITIAL.
              lv_ftype = ls_d3-rollname.
            ELSE.
*             Kein Datenelement: der eingebaute Typ tritt an seine
*             Stelle, damit die Spalte „Typ / Datenelement" nicht leer
*             bleibt - dieselbe Darstellung wie in der CDS-Feldliste
*             (CHAR 120, INT4, STRG). Fuehrende Nullen der Laenge fallen
*             textuell weg, INT4 und STRG bleiben so ohne Laengenrest.
              DATA lv_flen TYPE string.
              lv_flen = ls_d3-leng.
              SHIFT lv_flen LEFT DELETING LEADING '0'.
              lv_ftype = |{ ls_d3-datatype } { lv_flen }|.
              CONDENSE lv_ftype.
            ENDIF.
            APPEND VALUE ty_field(
              name     = ls_d3-fieldname
              rollname = lv_ftype
              keyflag  = COND #( WHEN ls_d3-keyflag = 'X' THEN abap_true
                                 ELSE abap_false ) ) TO lt_f.
          ENDLOOP.
        ENDIF.

        IF lt_f IS INITIAL.
          RETURN.
        ENDIF.
        DATA(lo_o1) = NEW lcl_object( iv_type = CONV string( iv_type )
                                      iv_name = CONV string( iv_name ) ).
        lo_o1->set_note( lcl_t=>t( d = 'Feldliste' e = 'Field list' ) ).
        LOOP AT lt_f INTO DATA(ls_f).
          lo_o1->add_field( ls_f ).
        ENDLOOP.
        io_chapter->add_object( lo_o1 ).

*       A view is built on tables, and which ones - joined how - is the
*       first thing a reader wants. DD26S holds the base tables in their
*       order and names the foreign key the join runs over.
        IF iv_type = 'VIEW'.
          DATA lv_vw TYPE dd26s-viewname.
          lv_vw = iv_name.
          SELECT tabpos, tabname, fortabname, forfield FROM dd26s
            WHERE viewname = @lv_vw AND as4local = 'A'
            ORDER BY tabpos
            INTO TABLE @DATA(lt_bt).
          IF lt_bt IS NOT INITIAL.
            DATA(lo_bt) = NEW lcl_object( iv_type = CONV string( iv_type )
                                          iv_name = CONV string( iv_name ) ).
            lo_bt->set_note( lcl_t=>t( d = 'Basistabellen und Verknüpfung'
                                       e = 'Base tables and join' ) ).
            LOOP AT lt_bt INTO DATA(ls_bt).
              DATA(lv_join) = |{ lcl_t=>t( d = `Position` e = `position` ) }| &&
                              | { ls_bt-tabpos }|.
              IF ls_bt-fortabname IS NOT INITIAL
                 AND ls_bt-fortabname <> ls_bt-tabname.
                lv_join = |{ lv_join }, { lcl_t=>t( d = `verknüpft mit`
                                                    e = `joined to` ) }| &&
                          | { ls_bt-fortabname }|.
                IF ls_bt-forfield IS NOT INITIAL.
                  lv_join = |{ lv_join } { lcl_t=>t( d = `über` e = `via` ) }| &&
                            | { ls_bt-forfield }|.
                ENDIF.
              ENDIF.
              lo_bt->add_field( VALUE ty_field( name     = ls_bt-tabname
                                                rollname = lv_join ) ).
            ENDLOOP.
            io_chapter->add_object( lo_bt ).
          ENDIF.
        ENDIF.

      WHEN 'CLAS' OR 'INTF'.
        lv_cls = iv_name.
        SELECT cmpname, cmptype FROM seocompo
          WHERE clsname = @lv_cls
          ORDER BY cmptype, cmpname
          INTO TABLE @DATA(lt_c).
*       Kein Abbruch bei leerer Komponentenliste. Eine Klasse, die nur
*       eine Schnittstelle implementiert - ein Query Provider etwa -,
*       hat in SEOCOMPO nichts Eigenes, und die Implementierung stand
*       deshalb nie im Dokument.
        DATA(lo_o2) = NEW lcl_object( iv_type = CONV string( iv_type )
                                      iv_name = CONV string( iv_name ) ).
        lo_o2->set_note( lcl_t=>t( d = 'Komponenten' e = 'Components' ) ).

*       Oberklasse und implementierte Schnittstellen.
        SELECT refclsname, reltype FROM seometarel
          WHERE clsname = @lv_cls AND version = '1'
          ORDER BY reltype, refclsname
          INTO TABLE @DATA(lt_rel).
        LOOP AT lt_rel INTO DATA(ls_rel).
          lo_o2->add_field( VALUE ty_field(
            name     = ls_rel-refclsname
            rollname = COND #( WHEN ls_rel-reltype = '1'
                               THEN lcl_t=>t( d = 'Schnittstelle' e = 'interface' )
                               WHEN ls_rel-reltype = '2'
                               THEN lcl_t=>t( d = 'Oberklasse' e = 'superclass' )
                               ELSE |{ lcl_t=>t( d = `Beziehung` e = `relation` ) } { ls_rel-reltype }| ) ) ).
        ENDLOOP.
        " Continued below
        LOOP AT lt_c INTO DATA(ls_c).
          DATA lv_tkind TYPE string.
          CASE ls_c-cmptype.
            WHEN '0'. lv_tkind = lcl_t=>t( d = 'Attribut' e = 'attribute' ).
            WHEN '1'. lv_tkind = lcl_t=>t( d = 'Methode' e = 'method' ).
            WHEN '2'. lv_tkind = lcl_t=>t( d = 'Ereignis' e = 'event' ).
            WHEN '3'. lv_tkind = lcl_t=>t( d = 'Typ' e = 'type' ).
            WHEN OTHERS. lv_tkind = |{ lcl_t=>t( d = `Typ` e = `type` ) } { ls_c-cmptype }|.
          ENDCASE.
          lo_o2->add_field( VALUE ty_field( name     = ls_c-cmpname
                                            rollname = lv_tkind ) ).
        ENDLOOP.

*       Implementierte Schnittstellenmethoden. SEOCOMPO fuehrt sie nicht,
*       sie gehoeren der Schnittstelle. Im Methodenverzeichnis des
*       Klassenpools stehen sie als SCHNITTSTELLE~METHODE.
        SELECT methodname FROM tmdir
          WHERE classname = @lv_cls AND methodname LIKE '%~%'
          ORDER BY methodname
          INTO TABLE @DATA(lt_im).
        LOOP AT lt_im INTO DATA(ls_im).
          lo_o2->add_field( VALUE ty_field(
            name     = ls_im-methodname
            rollname = lcl_t=>t( d = 'Methode (Schnittstelle)'
                                 e = 'method (interface)' ) ) ).
        ENDLOOP.

*       Lokale Klassen im Implementierungsteil. Ein Behavior-Pool ist
*       nach aussen leer; die Handler, die die Logik tragen, stehen als
*       lokale Klassen im CCIMP-Include. Kein Katalog kennt sie, also
*       wird der Quelltext gelesen.
        DATA lv_ccimp TYPE syrepid.
        DATA lt_cci   TYPE STANDARD TABLE OF string WITH EMPTY KEY.
        DATA lv_lcl   TYPE string.
        DATA lv_nloc  TYPE i.
        CLEAR: lt_cci, lv_lcl, lv_nloc.
        lv_ccimp = lv_cls.
        DATA(lv_ccl) = strlen( lv_cls ).
        WHILE lv_ccl < 30.
          lv_ccimp = |{ lv_ccimp }=|.
          lv_ccl = lv_ccl + 1.
        ENDWHILE.
        lv_ccimp = |{ lv_ccimp }CCIMP|.
        READ REPORT lv_ccimp INTO lt_cci.
        LOOP AT lt_cci INTO DATA(lv_cc).
          IF lv_cc IS INITIAL OR lv_cc(1) = '*'.
            CONTINUE.
          ENDIF.
          DATA(lv_ccu) = to_upper( condense( lv_cc ) ).
          REPLACE ALL OCCURRENCES OF ':' IN lv_ccu WITH ` `.
          REPLACE ALL OCCURRENCES OF '.' IN lv_ccu WITH ` `.
          CONDENSE lv_ccu.
          IF lv_ccu CP 'CLASS * DEFINITION*'
             AND NOT lv_ccu CS 'DEFERRED' AND NOT lv_ccu CS ' LOAD'.
            SPLIT lv_ccu AT ` ` INTO DATA(lv_ccw1) lv_lcl DATA(lv_ccrest).
            lo_o2->add_field( VALUE ty_field(
              name     = to_lower( lv_lcl )
              rollname = lcl_t=>t( d = 'lokale Klasse' e = 'local class' ) ) ).
            lv_nloc = lv_nloc + 1.
          ELSEIF lv_lcl IS NOT INITIAL
                 AND ( lv_ccu CP 'METHODS *' OR lv_ccu CP 'CLASS-METHODS *' ).
            SPLIT lv_ccu AT ` ` INTO DATA(lv_ccm1) DATA(lv_ccm2) DATA(lv_ccm3).
            REPLACE ALL OCCURRENCES OF ',' IN lv_ccm2 WITH ``.
            lo_o2->add_field( VALUE ty_field(
              name     = |{ to_lower( lv_lcl ) }->{ to_lower( lv_ccm2 ) }|
              rollname = lcl_t=>t( d = 'lokale Methode' e = 'local method' ) ) ).
            lv_nloc = lv_nloc + 1.
          ELSEIF lv_ccu CP 'ENDCLASS*'.
            CLEAR lv_lcl.
          ENDIF.
        ENDLOOP.

        IF lt_c IS NOT INITIAL OR lt_rel IS NOT INITIAL
           OR lt_im IS NOT INITIAL OR lv_nloc > 0.
          io_chapter->add_object( lo_o2 ).
        ENDIF.

      WHEN 'IDOC'.

*       Ein Basistyp stand bisher als blosse Kopfzeile im Dokument. Drei
*       Sichten machen ihn lesbar, und alle drei zeigt SAP in eigenen
*       Transaktionen:
*
*         WE60  die Segmenthierarchie - Ebene, Vatersegment, Muss und
*               Wiederholbereich. Das ist der Baum, den WE30 pflegt.
*         WE82  welche Nachrichtentypen auf diesem Basistyp fahren.
*         WE57  welche Bausteine ihn verarbeiten, je Richtung.
*
*       Die Hierarchie kommt aus derselben Schnittstelle, aus der auch
*       die Definitionsdaten stammen - IDOCTYPE_READ. Die beiden
*       Zuordnungen stehen in EDIMSG und EDIFCT.
        DATA lv_ity  TYPE edi_iapi00-idoctyp.
        DATA ls_iat  TYPE edi_iapi01.
        DATA lt_isy  TYPE STANDARD TABLE OF edi_iapi02 WITH EMPTY KEY.

        lv_ity = iv_name.
        CALL FUNCTION 'IDOCTYPE_READ'
          EXPORTING  pi_idoctyp         = lv_ity
                     pi_check_authority = abap_true
          IMPORTING  pe_attributes      = ls_iat
          TABLES     pt_syntax          = lt_isy
          EXCEPTIONS object_not_found   = 1
                     no_authority       = 2
                     db_error           = 3
                     OTHERS             = 4.

        IF sy-subrc = 0 AND lt_isy IS NOT INITIAL.

          DATA(lo_ih) = NEW lcl_object( iv_type = CONV string( iv_type )
                                        iv_name = CONV string( iv_name ) ).
          lo_ih->set_note( lcl_t=>t( d = 'Segmenthierarchie (WE60)'
                                     e = 'Segment hierarchy (WE60)' ) ).

          SORT lt_isy BY nr.
          LOOP AT lt_isy INTO DATA(ls_isy).

            DATA lv_ihk TYPE string.
            CLEAR lv_ihk.

*           Die Ebene sagt, wie tief das Segment haengt; das
*           Vatersegment, woran. Beides zusammen ist der Baum.
*           Ebene und Wiederholbereich sind NUMC und kaemen sonst mit
*           fuehrenden Nullen heraus - 0000000001..0000009999 statt
*           1..9999, wie WE60 es zeigt.
*
*           Abgeschnitten wird textuell, nicht gerechnet: OCCMIN und
*           OCCMAX sind NUMC(10), und der Wert 9999999999 - die Marke
*           fuer unbegrenzt - passt in kein TYPE I. Der erste Versuch
*           tat genau das und endete in BCD_OVERFLOW.
            DATA lv_lvl  TYPE string.
            DATA lv_min  TYPE string.
            DATA lv_max2 TYPE string.

            lv_lvl  = ls_isy-hlevel.
            lv_min  = ls_isy-occmin.
            lv_max2 = ls_isy-occmax.
            SHIFT lv_lvl  LEFT DELETING LEADING '0'.
            SHIFT lv_min  LEFT DELETING LEADING '0'.
            SHIFT lv_max2 LEFT DELETING LEADING '0'.
            IF lv_lvl  IS INITIAL. lv_lvl  = '0'. ENDIF.
            IF lv_min  IS INITIAL. lv_min  = '0'. ENDIF.
            IF lv_max2 IS INITIAL. lv_max2 = '0'. ENDIF.

            lv_ihk = |{ lcl_t=>t( d = `Ebene` e = `level` ) } { lv_lvl }|.
            IF ls_isy-parseg IS NOT INITIAL.
              lv_ihk = |{ lv_ihk }, { lcl_t=>t( d = `unter` e = `under` ) }| &&
                       | { ls_isy-parseg }|.
            ENDIF.
            IF ls_isy-mustfl = abap_true.
              lv_ihk = |{ lv_ihk }, { lcl_t=>t( d = `Mussfeld` e = `mandatory` ) }|.
            ENDIF.
            lv_ihk = |{ lv_ihk }, { lv_min }..{ lv_max2 }|.

            lo_ih->add_field( VALUE ty_field( name     = ls_isy-segtyp
                                              rollname = lv_ihk ) ).
          ENDLOOP.
          io_chapter->add_object( lo_ih ).
        ENDIF.

*       WE82: Nachrichtentypen auf diesem Basistyp. Ohne eine solche
*       Zuordnung faehrt der Basistyp nirgends - er waere eine
*       Struktur ohne Verkehr.
        SELECT mestyp, cimtyp, released, actflag FROM edimsg
          WHERE idoctyp = @lv_ity
          ORDER BY mestyp, cimtyp
          INTO TABLE @DATA(lt_msg).

        IF lt_msg IS NOT INITIAL.
          DATA(lo_im) = NEW lcl_object( iv_type = CONV string( iv_type )
                                        iv_name = CONV string( iv_name ) ).
          lo_im->set_note( lcl_t=>t( d = 'Nachrichtentypen (WE82)'
                                     e = 'Message types (WE82)' ) ).
          LOOP AT lt_msg INTO DATA(ls_msg).
            DATA lv_imk TYPE string.
            CLEAR lv_imk.
            IF ls_msg-cimtyp IS NOT INITIAL.
              lv_imk = |{ lcl_t=>t( d = `Erweiterung` e = `extension` ) }| &&
                       | { ls_msg-cimtyp }|.
            ENDIF.
            IF ls_msg-released IS NOT INITIAL.
              lv_imk = |{ lv_imk } { lcl_t=>t( d = `ab Release`
                                               e = `from release` ) } | &&
                       |{ ls_msg-released }|.
            ENDIF.
            IF ls_msg-actflag IS NOT INITIAL.
              lv_imk = |{ lv_imk } { lcl_t=>t( d = `(inaktiv)`
                                               e = `(inactive)` ) }|.
            ENDIF.
            CONDENSE lv_imk.
            lo_im->add_field( VALUE ty_field( name     = ls_msg-mestyp
                                              rollname = lv_imk ) ).
          ENDLOOP.
          io_chapter->add_object( lo_im ).
        ENDIF.

*       WE57: welcher Baustein verarbeitet den Typ, und in welcher
*       Richtung. Das ist die Stelle, an der ein IDoc auf Code trifft.
        SELECT fctnam, mestyp, cimtyp, direct, objnam FROM edifct
          WHERE idoctyp = @lv_ity
          ORDER BY direct, fctnam
          INTO TABLE @DATA(lt_fct).

        IF lt_fct IS NOT INITIAL.
          DATA(lo_if) = NEW lcl_object( iv_type = CONV string( iv_type )
                                        iv_name = CONV string( iv_name ) ).
          lo_if->set_note( lcl_t=>t( d = 'Verarbeitende Bausteine (WE57)'
                                     e = 'Processing modules (WE57)' ) ).
          LOOP AT lt_fct INTO DATA(ls_fct).
            DATA lv_ifk TYPE string.
            CASE ls_fct-direct.
              WHEN '1'. lv_ifk = lcl_t=>t( d = 'ausgehend' e = 'outbound' ).
              WHEN '2'. lv_ifk = lcl_t=>t( d = 'eingehend' e = 'inbound' ).
              WHEN OTHERS. lv_ifk = |{ lcl_t=>t( d = `Richtung` e = `direction` ) }| &&
                                    | { ls_fct-direct }|.
            ENDCASE.
            IF ls_fct-mestyp IS NOT INITIAL.
              lv_ifk = |{ lv_ifk }, { ls_fct-mestyp }|.
            ENDIF.
            IF ls_fct-cimtyp IS NOT INITIAL.
              lv_ifk = |{ lv_ifk }, { lcl_t=>t( d = `Erweiterung`
                                                e = `extension` ) } | &&
                       |{ ls_fct-cimtyp }|.
            ENDIF.
            IF ls_fct-objnam IS NOT INITIAL.
              lv_ifk = |{ lv_ifk }, { lcl_t=>t( d = `Objekttyp`
                                                e = `object type` ) } | &&
                       |{ ls_fct-objnam }|.
            ENDIF.
            lo_if->add_field( VALUE ty_field( name     = ls_fct-fctnam
                                              rollname = lv_ifk ) ).
          ENDLOOP.
          io_chapter->add_object( lo_if ).
        ENDIF.

      WHEN 'PROG'.
        " Text elements carry the actual operating instructions of a report:
        " title, selection texts, text symbols and list headings. READ
        " TEXTPOOL fetches them in one kernel call without database access.
        DATA lt_tp   TYPE STANDARD TABLE OF textpool.
        DATA lv_prog TYPE syrepid.
        lv_prog = iv_name.
        READ TEXTPOOL lv_prog INTO lt_tp LANGUAGE mv_langu.
        IF lt_tp IS INITIAL AND mv_falb = abap_true AND mv_flang <> mv_langu.
          READ TEXTPOOL lv_prog INTO lt_tp LANGUAGE mv_flang.
        ENDIF.
        IF lt_tp IS INITIAL.
          RETURN.
        ENDIF.
        DATA(lo_tp) = NEW lcl_object( iv_type = CONV string( iv_type )
                                      iv_name = CONV string( iv_name ) ).
        lo_tp->set_note( lcl_t=>t( d = 'Textelemente' e = 'Text elements' ) ).
        LOOP AT lt_tp INTO DATA(ls_tp).
          DATA lv_tpkind TYPE string.
          CASE ls_tp-id.
            WHEN 'R'. lv_tpkind = lcl_t=>t( d = 'Titel' e = 'Title' ).
            WHEN 'S'. lv_tpkind = lcl_t=>t( d = 'Selektionstext' e = 'Selection text' ).
            WHEN 'I'. lv_tpkind = lcl_t=>t( d = 'Textsymbol' e = 'Text symbol' ).
            WHEN 'H'. lv_tpkind = lcl_t=>t( d = 'Ueberschrift' e = 'List heading' ).
            WHEN OTHERS. lv_tpkind = CONV string( ls_tp-id ).
          ENDCASE.
          lo_tp->add_field( VALUE ty_field(
            name     = |{ lv_tpkind } { ls_tp-key }|
            rollname = ls_tp-entry ) ).
        ENDLOOP.
        io_chapter->add_object( lo_tp ).

      WHEN 'DOMA'.
        " For a domain with fixed values the value list is the documentation.
        DATA lv_dom TYPE dd07t-domname.
        lv_dom = iv_name.
        SELECT domvalue_l, ddtext, valpos FROM dd07t
          WHERE domname = @lv_dom AND ddlanguage = @mv_langu AND as4local = 'A'
          ORDER BY valpos
          INTO TABLE @DATA(lt_fix).
        IF lt_fix IS INITIAL AND mv_falb = abap_true AND mv_flang <> mv_langu.
          SELECT domvalue_l, ddtext, valpos FROM dd07t
            WHERE domname = @lv_dom AND ddlanguage = @mv_flang AND as4local = 'A'
            ORDER BY valpos
            INTO TABLE @lt_fix.
        ENDIF.
        IF lt_fix IS INITIAL.
          RETURN.
        ENDIF.
        DATA(lo_fix) = NEW lcl_object( iv_type = CONV string( iv_type )
                                       iv_name = CONV string( iv_name ) ).
        lo_fix->set_note( lcl_t=>t( d = 'Festwerte' e = 'Fixed values' ) ).
        LOOP AT lt_fix INTO DATA(ls_fix).
          lo_fix->add_field( VALUE ty_field( name     = ls_fix-domvalue_l
                                             rollname = ls_fix-ddtext ) ).
        ENDLOOP.
        io_chapter->add_object( lo_fix ).

      WHEN 'DTEL'.
        " Field labels are what the user sees on screen - often more
        " meaningful than the technical description.
        DATA lv_rol TYPE dd04t-rollname.
        lv_rol = iv_name.
        SELECT SINGLE scrtext_s, scrtext_m, scrtext_l, reptext FROM dd04t
          WHERE rollname = @lv_rol AND ddlanguage = @mv_langu AND as4local = 'A'
          INTO @DATA(ls_lab).
        IF sy-subrc <> 0 AND mv_falb = abap_true AND mv_flang <> mv_langu.
          SELECT SINGLE scrtext_s, scrtext_m, scrtext_l, reptext FROM dd04t
            WHERE rollname = @lv_rol AND ddlanguage = @mv_flang AND as4local = 'A'
            INTO @ls_lab.
        ENDIF.
        IF sy-subrc <> 0.
          RETURN.
        ENDIF.
        DATA(lo_lab) = NEW lcl_object( iv_type = CONV string( iv_type )
                                       iv_name = CONV string( iv_name ) ).
        lo_lab->set_note( lcl_t=>t( d = 'Feldbezeichner' e = 'Field labels' ) ).
        lo_lab->add_field( VALUE ty_field( name = lcl_t=>t( d = 'kurz' e = 'short' )
                                           rollname = ls_lab-scrtext_s ) ).
        lo_lab->add_field( VALUE ty_field( name = lcl_t=>t( d = 'mittel' e = 'medium' )
                                           rollname = ls_lab-scrtext_m ) ).
        lo_lab->add_field( VALUE ty_field( name = lcl_t=>t( d = 'lang' e = 'long' )
                                           rollname = ls_lab-scrtext_l ) ).
        lo_lab->add_field( VALUE ty_field( name = lcl_t=>t( d = 'Ueberschr' e = 'heading' )
                                           rollname = ls_lab-reptext ) ).
        io_chapter->add_object( lo_lab ).

      WHEN 'FUNC'.
        " The interface of a function module is its contract: what goes in,
        " what comes out, and which exceptions the caller has to handle.
        SELECT parameter, paramtype, structure, reference FROM fupararef
          WHERE funcname = @iv_name
          ORDER BY paramtype, pposition
          INTO TABLE @DATA(lt_par).
        IF lt_par IS INITIAL.
          RETURN.
        ENDIF.
        DATA(lo_par) = NEW lcl_object( iv_type = CONV string( iv_type )
                                       iv_name = CONV string( iv_name ) ).
        lo_par->set_note( lcl_t=>t( d = 'Schnittstelle' e = 'Interface' ) ).
        LOOP AT lt_par INTO DATA(ls_par).
          DATA lv_pkind TYPE string.
          CASE ls_par-paramtype.
            WHEN 'I'. lv_pkind = lcl_t=>t( d = 'Import' e = 'importing' ).
            WHEN 'E'. lv_pkind = lcl_t=>t( d = 'Export' e = 'exporting' ).
            WHEN 'C'. lv_pkind = lcl_t=>t( d = 'Changing' e = 'changing' ).
            WHEN 'T'. lv_pkind = lcl_t=>t( d = 'Tabelle' e = 'tables' ).
            WHEN 'X'. lv_pkind = lcl_t=>t( d = 'Ausnahme' e = 'exception' ).
            WHEN OTHERS. lv_pkind = ls_par-paramtype.
          ENDCASE.
          DATA(lv_ptype) = COND string(
            WHEN ls_par-structure IS NOT INITIAL THEN ls_par-structure
            ELSE ls_par-reference ).
          lo_par->add_field( VALUE ty_field(
            name     = |{ lv_pkind } { ls_par-parameter }|
            rollname = lv_ptype ) ).
        ENDLOOP.
        io_chapter->add_object( lo_par ).

      WHEN 'FUGR'.
        " The module list is the table of contents of a function group.
        DATA lv_pn TYPE tfdir-pname.
        lv_pn = |SAPL{ iv_name }|.
        SELECT funcname FROM tfdir
          WHERE pname = @lv_pn
          ORDER BY funcname
          INTO TABLE @DATA(lt_fm).
        IF lt_fm IS INITIAL.
          RETURN.
        ENDIF.
        DATA(lo_fm) = NEW lcl_object( iv_type = CONV string( iv_type )
                                      iv_name = CONV string( iv_name ) ).
        lo_fm->set_note( lcl_t=>t( d = 'Funktionsbausteine' e = 'Function modules' ) ).
        LOOP AT lt_fm INTO DATA(ls_fm).
          SELECT SINGLE stext FROM tftit
            WHERE spras = @mv_langu AND funcname = @ls_fm-funcname
            INTO @DATA(lv_fmt).
          IF sy-subrc <> 0 AND mv_falb = abap_true.
            SELECT SINGLE stext FROM tftit
              WHERE spras = @mv_flang AND funcname = @ls_fm-funcname
              INTO @lv_fmt.
          ENDIF.
          lo_fm->add_field( VALUE ty_field( name     = ls_fm-funcname
                                            rollname = lv_fmt ) ).
        ENDLOOP.
        io_chapter->add_object( lo_fm ).

      WHEN 'DDLS'.
        " Dependencies of the CDS view - the objects it consumes
        DATA lv_ddl TYPE ddldependency-ddlname.
        lv_ddl = iv_name.

*       Die Feldliste der Entitaet. Bei einer CDS-View steht sie nicht in
*       DD03L - dort liegt hoechstens der SQL-View, und eine View Entity
*       oder Custom Entity hat keinen. DD03ND fuehrt die Elemente unter
*       dem Entitaetsnamen, den DDLDEPENDENCY als STOB nennt.
        SELECT SINGLE objectname FROM ddldependency
          WHERE ddlname = @lv_ddl AND objecttype = 'STOB' AND state = 'A'
          INTO @DATA(lv_ent).
        IF lv_ent IS INITIAL.
          lv_ent = iv_name.
        ENDIF.
*       DD03ND gibt es erst ab 7.5x. Dynamisch gelesen bleibt die
*       Feldliste auf aelteren Staenden leer, statt dass der Report nicht
*       uebersetzt.
        TYPES: BEGIN OF ty_ef,
                 fieldname TYPE fieldname,
                 keyflag   TYPE keyflag,
                 rollname  TYPE rollname,
                 datatype  TYPE datatype_d,
                 leng      TYPE ddleng,
               END OF ty_ef.
        DATA lt_ef    TYPE STANDARD TABLE OF ty_ef WITH EMPTY KEY.
        DATA lv_eftab TYPE tabname.
        CLEAR lt_ef.
        lv_eftab = 'DD03ND'.
        TRY.
            SELECT fieldname, keyflag, rollname, datatype, leng FROM (lv_eftab)
              WHERE strucobjn = @lv_ent AND as4local = 'A'
              ORDER BY position
              INTO CORRESPONDING FIELDS OF TABLE @lt_ef.
          CATCH cx_root.
            CLEAR lt_ef.
        ENDTRY.
        IF lt_ef IS NOT INITIAL.
          DATA(lo_oef) = NEW lcl_object( iv_type = CONV string( iv_type )
                                         iv_name = CONV string( iv_name ) ).
          lo_oef->set_note( lcl_t=>t( d = 'Feldliste' e = 'Field list' ) ).
          DATA lt_efseen TYPE STANDARD TABLE OF string WITH EMPTY KEY.
          CLEAR lt_efseen.
          LOOP AT lt_ef INTO DATA(ls_ef).
            READ TABLE lt_efseen TRANSPORTING NO FIELDS
                 WITH KEY table_line = CONV string( ls_ef-fieldname ).
            IF sy-subrc = 0.
              CONTINUE.
            ENDIF.
            APPEND CONV string( ls_ef-fieldname ) TO lt_efseen.
            DATA lv_eft TYPE string.
            IF ls_ef-rollname IS NOT INITIAL.
              lv_eft = ls_ef-rollname.
            ELSE.
*             NUMC - ohne Rechnen, die Nullen fallen textuell weg.
              DATA lv_efl TYPE string.
              lv_efl = ls_ef-leng.
              SHIFT lv_efl LEFT DELETING LEADING '0'.
              lv_eft = |{ ls_ef-datatype } { lv_efl }|.
              CONDENSE lv_eft.
            ENDIF.
            lo_oef->add_field( VALUE ty_field(
              name     = ls_ef-fieldname
              rollname = lv_eft
              keyflag  = COND #( WHEN ls_ef-keyflag = 'X' THEN abap_true
                                 ELSE abap_false ) ) ).
          ENDLOOP.
          io_chapter->add_object( lo_oef ).
        ENDIF.
        " The view itself is listed in the dependency table as well and is
        " hidden - it is not a usage.
        SELECT objectname, objecttype, state FROM ddldependency
          WHERE ddlname = @lv_ddl AND state = 'A' AND objectname <> @lv_ddl
          ORDER BY objecttype, objectname
          INTO TABLE @DATA(lt_d).
        IF lt_d IS INITIAL.
          RETURN.
        ENDIF.
        DATA(lo_o3) = NEW lcl_object( iv_type = CONV string( iv_type )
                                      iv_name = CONV string( iv_name ) ).
        lo_o3->set_note( lcl_t=>t( d = 'Verwendete Objekte' e = 'Objects used' ) ).
        LOOP AT lt_d INTO DATA(ls_d).
          lo_o3->add_field( VALUE ty_field( name     = ls_d-objectname
                                            rollname = ls_d-objecttype ) ).
        ENDLOOP.
        io_chapter->add_object( lo_o3 ).

      WHEN 'SRVB'.
*       Ein Service-Binding hat keinen Quelltext, und die volle Struktur
*       ist ueberwiegend Verwaltungskram. Drei Angaben tragen die
*       Aussage: die Bindungsart (z.B. ODATA V2), die verknuepfte
*       Service-Definition - die sonst nirgends im Dokument steht - und
*       ob das Binding veroeffentlicht ist. Das gehoert zu den Details
*       (nicht an die Definitionsdaten gebunden), damit es auch dann
*       erscheint, wenn nur die Details gezogen werden.
        FIELD-SYMBOLS <ls_sba> TYPE any.
        FIELD-SYMBOLS <ls_sbc> TYPE any.
        FIELD-SYMBOLS <lt_sbs> TYPE ANY TABLE.
        FIELD-SYMBOLS <lt_sbv> TYPE ANY TABLE.
        DATA(lr_sba) = lcl_wb=>srvb_data( `TY_OBJECT_DATA` ).
        IF lr_sba IS NOT BOUND.
          RETURN.
        ENDIF.
        ASSIGN lr_sba->* TO <ls_sba>.
        DATA(lo_sbd) = lcl_wb=>read( iv_type = 'SRVB' iv_name = iv_name ).
        IF lo_sbd IS NOT BOUND.
          RETURN.
        ENDIF.
        lcl_wb=>all_data( EXPORTING io_data = lo_sbd
                          CHANGING  cs_data = <ls_sba> ).
        IF lcl_wb=>comp( is_data = <ls_sba> iv_path = `CONTENT-BIND_TYPE` ) IS INITIAL.
          RETURN.
        ENDIF.

        DATA(lo_sbo) = NEW lcl_object( iv_type = CONV string( iv_type )
                                       iv_name = CONV string( iv_name ) ).
        lo_sbo->set_note( lcl_t=>t( d = 'Service-Binding' e = 'Service binding' ) ).

*       Bindungsart aus Kategorie und Version, z.B. "ODATA V2"; faellt
*       einer der beiden aus, bleibt der technische Bindungstyp.
        DATA lv_bkind TYPE string.
        lv_bkind = condense( |{ lcl_wb=>comp( is_data = <ls_sba>
                                              iv_path = `CONTENT-BIND_TYPE_CATEGORY` ) } | &&
                             |{ lcl_wb=>comp( is_data = <ls_sba>
                                              iv_path = `CONTENT-BIND_TYPE_VERSION` ) }| ).
        IF lv_bkind IS INITIAL.
          lv_bkind = lcl_wb=>comp( is_data = <ls_sba> iv_path = `CONTENT-BIND_TYPE` ).
        ENDIF.
        lo_sbo->add_field( VALUE ty_field(
          name     = lcl_t=>t( d = 'Bindungsart' e = 'Binding type' )
          rollname = lv_bkind ) ).

*       Die verknuepfte Service-Definition steht in den Versionszeilen
*       der Services; bei einem Binding meist fuer alle Versionen
*       dieselbe. Jede genannte wird einmal aufgefuehrt.
        DATA lt_srvd TYPE STANDARD TABLE OF string WITH EMPTY KEY.
        CLEAR lt_srvd.
        ASSIGN COMPONENT 'CONTENT' OF STRUCTURE <ls_sba> TO <ls_sbc>.
        IF sy-subrc = 0.
          ASSIGN COMPONENT 'SERVICES' OF STRUCTURE <ls_sbc> TO <lt_sbs>.
          IF sy-subrc = 0.
            LOOP AT <lt_sbs> ASSIGNING FIELD-SYMBOL(<ls_sbsrv>).
              ASSIGN COMPONENT 'SERVICE_CONTENT' OF STRUCTURE <ls_sbsrv> TO <lt_sbv>.
              IF sy-subrc <> 0.
                CONTINUE.
              ENDIF.
              LOOP AT <lt_sbv> ASSIGNING FIELD-SYMBOL(<ls_sbver>).
                DATA(lv_sbsd) = lcl_wb=>comp( is_data = <ls_sbver> iv_path = `SRVD_REF-NAME` ).
                IF lv_sbsd IS INITIAL.
                  CONTINUE.
                ENDIF.
                READ TABLE lt_srvd TRANSPORTING NO FIELDS
                     WITH KEY table_line = lv_sbsd.
                IF sy-subrc <> 0.
                  APPEND lv_sbsd TO lt_srvd.
                ENDIF.
              ENDLOOP.
            ENDLOOP.
          ENDIF.
        ENDIF.
        LOOP AT lt_srvd INTO DATA(lv_srvd).
          lo_sbo->add_field( VALUE ty_field(
            name     = lcl_t=>t( d = 'Service-Definition' e = 'Service definition' )
            rollname = lv_srvd ) ).
        ENDLOOP.

        lo_sbo->add_field( VALUE ty_field(
          name     = lcl_t=>t( d = 'Veröffentlicht' e = 'Published' )
          rollname = COND #( WHEN lcl_wb=>comp( is_data = <ls_sba>
                                                iv_path = `PUBLISHED` ) = abap_true
                             THEN lcl_t=>t( d = 'ja' e = 'yes' )
                             ELSE lcl_t=>t( d = 'nein' e = 'no' ) ) ) ).

        io_chapter->add_object( lo_sbo ).

      WHEN 'SSFO'.
*       Ein Smart Form ist ein Baum aus Knoten mit einer Formular-
*       schnittstelle und globalen Definitionen. Anders als bei einer
*       Tabelle steht davon nichts in einer lesbaren DDIC-Tabelle; die
*       Struktur liegt allein im Objektmodell des Form Builders vor. Es
*       wird einmal geladen und in drei Bloecke ueberfuehrt:
*       Schnittstelle, globale Definitionen, Knotenbaum.
        DATA(lo_sf) = ssfo_form( iv_name ).
        IF lo_sf IS NOT BOUND.
          RETURN.
        ENDIF.

*       Formularschnittstelle: Import-/Export-/Tabellenparameter und
*       Ausnahmen mit Richtung und Typ.
        IF lo_sf->interface IS NOT INITIAL.
          DATA(lo_ifc) = NEW lcl_object( iv_type = CONV string( iv_type )
                                         iv_name = CONV string( iv_name ) ).
          lo_ifc->set_note( lcl_t=>t( d = 'Formularschnittstelle' e = 'Form interface' ) ).
          LOOP AT lo_sf->interface INTO DATA(ls_ifp).
            DATA lv_iodir TYPE string.
            CASE ls_ifp-iotype.
              WHEN 'I'. lv_iodir = lcl_t=>t( d = 'Import'   e = 'Import' ).
              WHEN 'E'. lv_iodir = lcl_t=>t( d = 'Export'   e = 'Export' ).
              WHEN 'T'. lv_iodir = lcl_t=>t( d = 'Tabelle'  e = 'Table' ).
              WHEN 'X'. lv_iodir = lcl_t=>t( d = 'Ausnahme' e = 'Exception' ).
              WHEN OTHERS. lv_iodir = ls_ifp-iotype.
            ENDCASE.
            DATA(lv_iodef) = condense( |{ ls_ifp-typing } { ls_ifp-typename }| ).
            DATA(lv_iorn)  = COND string( WHEN lv_iodef IS NOT INITIAL
                                          THEN |{ lv_iodir }: { lv_iodef }|
                                          ELSE lv_iodir ).
            IF ls_ifp-optional = 'X'.
              lv_iorn = |{ lv_iorn } ({ lcl_t=>t( d = 'optional' e = 'optional' ) })|.
            ENDIF.
            lo_ifc->add_field( VALUE ty_field( name     = CONV string( ls_ifp-name )
                                               rollname = lv_iorn ) ).
          ENDLOOP.
          io_chapter->add_object( lo_ifc ).
        ENDIF.

*       Globale Definitionen: global vereinbarte Datenfelder der Form.
        IF lo_sf->gdata IS NOT INITIAL.
          DATA(lo_gbl) = NEW lcl_object( iv_type = CONV string( iv_type )
                                         iv_name = CONV string( iv_name ) ).
          lo_gbl->set_note( lcl_t=>t( d = 'Globale Definitionen' e = 'Global definitions' ) ).
          LOOP AT lo_sf->gdata INTO DATA(ls_gbl).
            DATA(lv_gdef) = condense( |{ ls_gbl-typing } { ls_gbl-typename }| ).
            IF ls_gbl-constant = 'X'.
              lv_gdef = condense( |{ lv_gdef } ({ lcl_t=>t( d = 'Konstante' e = 'constant' ) })| ).
            ENDIF.
            lo_gbl->add_field( VALUE ty_field( name     = CONV string( ls_gbl-name )
                                               rollname = lv_gdef ) ).
          ENDLOOP.
          io_chapter->add_object( lo_gbl ).
        ENDIF.

*       Knotenbaum: die Struktur des Formulars, rekursiv aus den
*       Seitenbaeumen der Varianten. Die Gliederungsnummer traegt die
*       Hierarchie, damit sie in jedem Ausgabeformat erhalten bleibt.
        DATA lt_ntree TYPE ty_fields.
        CLEAR lt_ntree.
        LOOP AT lo_sf->varheader INTO DATA(ls_vh).
          ssfo_tree( EXPORTING io_node = ls_vh-pagetree iv_outline = ``
                     CHANGING  ct_field = lt_ntree ).
        ENDLOOP.
        IF lt_ntree IS NOT INITIAL.
          DATA(lo_ntr) = NEW lcl_object( iv_type = CONV string( iv_type )
                                         iv_name = CONV string( iv_name ) ).
          lo_ntr->set_note( lcl_t=>t( d = 'Knotenbaum' e = 'Node tree' ) ).
          LOOP AT lt_ntree INTO DATA(ls_ntn).
            lo_ntr->add_field( ls_ntn ).
          ENDLOOP.
          io_chapter->add_object( lo_ntr ).
        ENDIF.

      WHEN 'SFPI'.
*       Eine Adobe-Form-Schnittstelle bringt Formularschnittstelle und
*       globale Definitionen mit; das Coding steht im Quelltextteil.
        add_sfp_ifc_blocks( iv_type    = iv_type
                            iv_name    = iv_name
                            iv_ifname  = iv_name
                            io_chapter = io_chapter ).

      WHEN 'SFPF'.
*       Ein Adobe-Formular besteht aus einer Schnittstelle (eigenes
*       Objekt), einem Kontext (Datenbindung) und einem Layout. Es wird
*       einmal geladen und in Eigenschaften, Schnittstelle und Kontext-
*       baum ueberfuehrt. Das Layout ist ein XFA-/DOCX-Artefakt und wird
*       nur mit seiner Technologie vermerkt.
        DATA(lo_aff) = sfpf_form( iv_name ).
        IF lo_aff IS NOT BOUND.
          RETURN.
        ENDIF.
        DATA(lv_ifn) = lo_aff->get_interface_name( ).

*       Formulareigenschaften.
        DATA(lo_prp) = NEW lcl_object( iv_type = CONV string( iv_type )
                                       iv_name = CONV string( iv_name ) ).
        lo_prp->set_note( lcl_t=>t( d = 'Formulareigenschaften' e = 'Form properties' ) ).
        lo_prp->add_field( VALUE ty_field(
          name     = lcl_t=>t( d = 'Schnittstelle' e = 'Interface' )
          rollname = CONV string( lv_ifn ) ) ).
        DATA lv_ftl TYPE string.
        CASE lo_aff->get_form_type( ).
          WHEN 'M'.    lv_ftl = lcl_t=>t( d = 'migriert (aus Smart Form)' e = 'migrated (from Smart Form)' ).
          WHEN 'G'.    lv_ftl = lcl_t=>t( d = 'Guided Procedures' e = 'Guided Procedures' ).
          WHEN OTHERS. lv_ftl = lcl_t=>t( d = 'normal' e = 'normal' ).
        ENDCASE.
        lo_prp->add_field( VALUE ty_field(
          name     = lcl_t=>t( d = 'Formulartyp' e = 'Form type' )
          rollname = lv_ftl ) ).
        DATA(lo_lay) = lo_aff->get_layout( ).
        DATA lv_tcl TYPE string.
        CASE lo_lay->get_form_tech( ).
          WHEN 'W'.    lv_tcl = 'DOCX (Microsoft Word)'.
          WHEN 'C'.    lv_tcl = 'Crystal Reports'.
          WHEN 'F'.    lv_tcl = 'XSL-FO'.
          WHEN 'X'.    lv_tcl = 'XForms'.
          WHEN OTHERS. lv_tcl = 'XFA (Adobe LiveCycle Designer)'.
        ENDCASE.
        lo_prp->add_field( VALUE ty_field(
          name     = lcl_t=>t( d = 'Layout-Technologie' e = 'Layout technology' )
          rollname = lv_tcl ) ).
        io_chapter->add_object( lo_prp ).

*       Schnittstelle und globale Definitionen der referenzierten SFPI.
        IF lv_ifn IS NOT INITIAL.
          add_sfp_ifc_blocks( iv_type    = iv_type
                              iv_name    = iv_name
                              iv_ifname  = CONV sobj_name( lv_ifn )
                              io_chapter = io_chapter ).
        ENDIF.

*       Kontextbaum: die Datenbindung des Formulars, rekursiv aus den
*       Kindern der Kontextwurzel. Die Gliederungsnummer traegt die
*       Hierarchie, damit sie in jedem Ausgabeformat erhalten bleibt.
        DATA lt_ctree TYPE ty_fields.
        DATA(lo_croot) = lo_aff->get_context( ).
        IF lo_croot IS BOUND.
          DATA lv_ci   TYPE i.
          DATA(lo_cch) = lo_croot->get_child( ).
          WHILE lo_cch IS BOUND.
            lv_ci = lv_ci + 1.
            sfpf_context( EXPORTING io_node = lo_cch iv_outline = |{ lv_ci }|
                          CHANGING  ct_field = lt_ctree ).
            lo_cch = lo_cch->get_successor( ).
          ENDWHILE.
        ENDIF.
        IF lt_ctree IS NOT INITIAL.
          DATA(lo_ctx) = NEW lcl_object( iv_type = CONV string( iv_type )
                                         iv_name = CONV string( iv_name ) ).
          lo_ctx->set_note( lcl_t=>t( d = 'Kontext' e = 'Context' ) ).
          LOOP AT lt_ctree INTO DATA(ls_ctn).
            lo_ctx->add_field( ls_ctn ).
          ENDLOOP.
          io_chapter->add_object( lo_ctx ).
        ENDIF.

    ENDCASE.

  ENDMETHOD.

  METHOD start_object.
*   The type codes follow the Object Navigator so that the field reads the
*   same way it does in SE80.
    DATA lv_name TYPE sobj_name.
    lv_name = mv_sval.

    CASE mv_stype.
      WHEN 'K'.  rs_obj = VALUE #( type = 'DEVC' name = lv_name ).
      WHEN 'P'.  rs_obj = VALUE #( type = 'PROG' name = lv_name ).
      WHEN 'FF'. rs_obj = VALUE #( type = 'FUNC' name = lv_name ).
      WHEN 'F'.  rs_obj = VALUE #( type = 'FUGR' name = lv_name ).
      WHEN 'T'.  rs_obj = VALUE #( type = 'TABL' name = lv_name ).
      WHEN 'V'.  rs_obj = VALUE #( type = 'VIEW' name = lv_name ).
      WHEN 'D'.  rs_obj = VALUE #( type = 'DTEL' name = lv_name ).
      WHEN 'DO'. rs_obj = VALUE #( type = 'DOMA' name = lv_name ).
      WHEN 'W'.  rs_obj = VALUE #( type = 'DDLS' name = lv_name ).
      WHEN 'MX'. rs_obj = VALUE #( type = 'DDLX' name = lv_name ).
      WHEN 'BD'. rs_obj = VALUE #( type = 'BDEF' name = lv_name ).
      WHEN 'SD'. rs_obj = VALUE #( type = 'SRVD' name = lv_name ).
      WHEN 'SB'. rs_obj = VALUE #( type = 'SRVB' name = lv_name ).
*     Ein Segment traegt im Katalog TABL; die Definitionsermittlung
*     erkennt es dort und behandelt es als Segment.
      WHEN 'IS'. rs_obj = VALUE #( type = 'TABL' name = lv_name ).
      WHEN 'IT'. rs_obj = VALUE #( type = 'IDOC' name = lv_name ).
      WHEN 'U5'. rs_obj = VALUE #( type = 'WAPA' name = lv_name ).
      WHEN 'SF'. rs_obj = VALUE #( type = 'SSFO' name = lv_name ).
      WHEN 'AF'. rs_obj = VALUE #( type = 'SFPF' name = lv_name ).
      WHEN 'AI'. rs_obj = VALUE #( type = 'SFPI' name = lv_name ).
      WHEN 'C'.
*       A class and an interface share one input field, as in SE80. Which
*       of the two it is comes from the catalog.
        SELECT SINGLE object FROM tadir
          WHERE pgmid = 'R3TR' AND delflag = @abap_false AND object IN ( 'CLAS', 'INTF' )
            AND obj_name = @lv_name
          INTO @DATA(lv_obj).
        IF sy-subrc = 0.
          rs_obj = VALUE #( type = lv_obj name = lv_name ).
        ELSE.
          rs_obj = VALUE #( type = 'CLAS' name = lv_name ).
        ENDIF.
      WHEN OTHERS.
        rs_obj = VALUE #( type = 'DEVC' name = lv_name ).
    ENDCASE.
  ENDMETHOD.

  METHOD base_name.
*   A cross-reference entry carries a technical name such as
*   CL_ABAP_BROWSER\ME:SHOW_HTML. Only the part before the first backslash
*   is a repository object; the rest addresses a component inside it.
    DATA lv_base TYPE string.
    lv_base = iv_name.
    IF lv_base CS '\'.
      SPLIT lv_base AT '\' INTO lv_base DATA(lv_rest).
    ENDIF.
    CONDENSE lv_base.
    IF lv_base IS INITIAL OR strlen( lv_base ) > 40.
      RETURN.
    ENDIF.
    rv_base = lv_base.
  ENDMETHOD.

  METHOD own_names.
*   Which of these objects are this system's own development. The criterion
*   is the delivery unit of the package: HOME and LOCAL were built here,
*   everything else was shipped. That is the same line SAP itself draws,
*   and unlike a name check it also catches customer objects living in a
*   reserved namespace and SAP objects that start with a Z.
*
*   Whatever has no catalog entry is not returned and therefore counts as
*   not-our-own: constants of a type group such as ABAP_TRUE, kernel types
*   and the like. They would otherwise be the only thing left over in a
*   filtered list.
    IF it_name IS INITIAL.
      RETURN.
    ENDIF.

    SELECT obj_name, devclass FROM tadir
      FOR ALL ENTRIES IN @it_name
      WHERE pgmid = 'R3TR' AND delflag = @abap_false AND obj_name = @it_name-table_line
      INTO TABLE @DATA(lt_t).
    IF lt_t IS INITIAL.
      RETURN.
    ENDIF.

    DATA lt_dev TYPE STANDARD TABLE OF devclass.
    LOOP AT lt_t INTO DATA(ls_t).
      APPEND ls_t-devclass TO lt_dev.
    ENDLOOP.
    SORT lt_dev.
    DELETE ADJACENT DUPLICATES FROM lt_dev.

    SELECT devclass, dlvunit FROM tdevc
      FOR ALL ENTRIES IN @lt_dev
      WHERE devclass = @lt_dev-table_line
      INTO TABLE @DATA(lt_d).

    LOOP AT lt_t INTO ls_t.
      READ TABLE lt_d INTO DATA(ls_d) WITH KEY devclass = ls_t-devclass.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      IF ls_d-dlvunit IS INITIAL
         OR ls_d-dlvunit = 'HOME' OR ls_d-dlvunit = 'LOCAL'.
        APPEND ls_t-obj_name TO rt_own.
      ENDIF.
    ENDLOOP.

    SORT rt_own BY table_line.
    DELETE ADJACENT DUPLICATES FROM rt_own COMPARING table_line.
  ENDMETHOD.

  METHOD drop_sap.

    IF mv_nosap = abap_false OR ct_ref IS INITIAL.
      RETURN.
    ENDIF.

*   A function module has no catalog entry of its own; its function group
*   decides where it belongs.
    TYPES: BEGIN OF ty_map,
             name TYPE sobj_name,
             cat  TYPE sobj_name,
           END OF ty_map.
    DATA lt_map  TYPE STANDARD TABLE OF ty_map.
    DATA lt_name TYPE ty_names.

    LOOP AT ct_ref INTO DATA(ls_r).
      DATA(ls_m) = VALUE ty_map( name = ls_r-name cat = ls_r-name ).
      IF ls_r-type = 'FUNC'.
        ls_m-cat = func_group( CONV rs38l_fnam( ls_r-name ) ).
      ENDIF.
      APPEND ls_m TO lt_map.
      APPEND ls_m-cat TO lt_name.
    ENDLOOP.

    SORT lt_name BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_name COMPARING table_line.
    DATA(lt_own) = own_names( lt_name ).

*   An include may have no catalog entry at all, and then the package is
*   not available to decide with. It got here from the source of an
*   object that is already in the document, so it belongs to that
*   object - an include nobody catalogued is not SAP standard, and
*   without it the including program does not compile. SAP's own
*   includes do have a catalog entry and are filtered normally above.
    DATA lt_unkn TYPE ty_names.
    LOOP AT ct_ref INTO ls_r WHERE type = 'PROG'.
      READ TABLE lt_own TRANSPORTING NO FIELDS
           WITH KEY table_line = ls_r-name BINARY SEARCH.
      IF sy-subrc <> 0.
        APPEND ls_r-name TO lt_unkn.
      ENDIF.
    ENDLOOP.

    IF lt_unkn IS NOT INITIAL.
      SELECT obj_name FROM tadir
        FOR ALL ENTRIES IN @lt_unkn
        WHERE pgmid = 'R3TR' AND delflag = @abap_false AND object = 'PROG'
          AND obj_name = @lt_unkn-table_line
        INTO TABLE @DATA(lt_cat).
      SORT lt_cat BY table_line.

      SELECT name, subc FROM trdir
        FOR ALL ENTRIES IN @lt_unkn
        WHERE name = @lt_unkn-table_line
        INTO TABLE @DATA(lt_dir).

      LOOP AT lt_dir INTO DATA(ls_dir) WHERE subc = 'I'.
        READ TABLE lt_cat TRANSPORTING NO FIELDS
             WITH KEY table_line = ls_dir-name BINARY SEARCH.
        IF sy-subrc <> 0.
          APPEND ls_dir-name TO lt_own.
        ENDIF.
      ENDLOOP.
      SORT lt_own BY table_line.
      DELETE ADJACENT DUPLICATES FROM lt_own COMPARING table_line.
    ENDIF.

*   Building a new table instead of deleting inside the loop - DELETE
*   shifts the index under the cursor.
    DATA lt_keep TYPE ty_objrefs.
    DATA lv_cat  TYPE sobj_name.

    LOOP AT ct_ref INTO ls_r.
      lv_cat = ls_r-name.
      READ TABLE lt_map INTO ls_m WITH KEY name = ls_r-name.
      IF sy-subrc = 0.
        lv_cat = ls_m-cat.
      ENDIF.
      READ TABLE lt_own TRANSPORTING NO FIELDS
           WITH KEY table_line = lv_cat BINARY SEARCH.
      IF sy-subrc = 0.
        APPEND ls_r TO lt_keep.
      ENDIF.
    ENDLOOP.

    ct_ref = lt_keep.

  ENDMETHOD.

  METHOD resolve_repo_object.

    DATA lv_obj_name TYPE sobj_name.
    lv_obj_name = base_name( iv_name ).
    IF lv_obj_name IS INITIAL.
      RETURN.
    ENDIF.

    SELECT SINGLE object FROM tadir
      WHERE pgmid = 'R3TR' AND delflag = @abap_false
        AND object IN ( 'CLAS', 'INTF', 'TABL', 'VIEW', 'DTEL', 'DOMA',
                        'TTYP', 'DDLS', 'PROG', 'FUGR', 'MSAG', 'SHLP',
                        'ENQU', 'BDEF', 'SRVD', 'SRVB', 'DDLX', 'IDOC', 'WAPA',
                        'SSFO', 'SFPF', 'SFPI' )
        AND obj_name = @lv_obj_name
      INTO @DATA(lv_type).
    IF sy-subrc = 0.
      rs_ref = VALUE #( type = lv_type name = lv_obj_name ).
    ENDIF.
  ENDMETHOD.

  METHOD scan_source_calls.
*   What an object uses is written in its source, and the source is always
*   there - unlike the cross-reference index. CROSS is empty on many S/4
*   systems because SAPRSEUB was never run, and WBCROSSGT records only
*   global types, methods and data objects. Four things are picked up here:
*
*     CALL FUNCTION   function modules - in no index at all
*     SUBMIT          reports - likewise
*     SELECT/UPDATE   the tables the object reads and writes
*     =>, REF TO, NEW the classes and interfaces it uses
*
*   Every candidate is checked against the catalog afterwards. A name put
*   together at runtime, a local class or a work area that happens to look
*   like a table would otherwise end up in the document.
    DATA(lt_src) = source_lines( iv_type = iv_type iv_name = iv_name ).
    IF lt_src IS INITIAL.
      RETURN.
    ENDIF.

    DATA lv_up   TYPE string.
    DATA lv_hit  TYPE string.
    DATA ls_ref  TYPE ty_objref.
    DATA lt_hits TYPE STANDARD TABLE OF string.
    DATA lt_tab  TYPE STANDARD TABLE OF sobj_name.
    DATA lt_cls  TYPE STANDARD TABLE OF sobj_name.
    DATA lt_lit  TYPE STANDARD TABLE OF sobj_name.
    DATA lt_msg  TYPE STANDARD TABLE OF t100a-arbgb.
    DATA lt_fun  TYPE STANDARD TABLE OF rs38l_fnam.

    LOOP AT lt_src INTO DATA(lv_line).

      lv_up = to_upper( lv_line ).

*     Comments are not code. A trailing quote also ends the statement, so
*     everything behind it is dropped before the patterns run.
      SHIFT lv_up LEFT DELETING LEADING space.
      IF lv_up IS INITIAL OR lv_up(1) = '*'.
        CONTINUE.
      ENDIF.
      IF lv_up CS '"'.
        SPLIT lv_up AT '"' INTO lv_up DATA(lv_rest).
      ENDIF.

      FIND FIRST OCCURRENCE OF REGEX `CALL\s+FUNCTION\s+'([A-Z0-9_/][^']*)'`
        IN lv_up SUBMATCHES lv_hit ##REGEX_POSIX.
      IF sy-subrc = 0.
        APPEND CONV rs38l_fnam( lv_hit ) TO lt_fun.
      ENDIF.

      FIND FIRST OCCURRENCE OF REGEX `^SUBMIT\s+([A-Z0-9_/]+)`
        IN lv_up SUBMATCHES lv_hit ##REGEX_POSIX.
      IF sy-subrc = 0.
        CLEAR ls_ref.
        ls_ref-type = 'PROG'.
        ls_ref-name = lv_hit.
        ls_ref-kind = lcl_t=>t( d = 'Report-Aufruf' e = 'report call' ).
        APPEND ls_ref TO rt_ref.
      ENDIF.

*     Table access. Dynamic forms - FROM (lv_name) - and internal tables
*     - FROM @lt_x - do not match, the pattern insists on a letter.
      CLEAR lt_hits.
      FIND ALL OCCURRENCES OF REGEX
        `\b(?:FROM|JOIN|UPDATE)\s+([A-Z][A-Z0-9_/]{2,29})\b`
        IN lv_up RESULTS DATA(lt_r1) ##REGEX_POSIX.
      LOOP AT lt_r1 INTO DATA(ls_r1).
        DATA(ls_sub1) = ls_r1-submatches[ 1 ].
        APPEND CONV sobj_name( lv_up+ls_sub1-offset(ls_sub1-length) ) TO lt_tab.
      ENDLOOP.

      FIND ALL OCCURRENCES OF REGEX
        `^(?:INSERT|MODIFY|DELETE)\s+([A-Z][A-Z0-9_/]{2,29})\s+FROM\b`
        IN lv_up RESULTS DATA(lt_r2) ##REGEX_POSIX.
      LOOP AT lt_r2 INTO DATA(ls_r2).
        DATA(ls_sub2) = ls_r2-submatches[ 1 ].
        APPEND CONV sobj_name( lv_up+ls_sub2-offset(ls_sub2-length) ) TO lt_tab.
      ENDLOOP.

*     Classes and interfaces: static access, a reference variable, or NEW.
      FIND ALL OCCURRENCES OF REGEX
        `\b([A-Z/][A-Z0-9_/]{2,29})\s*=>`
        IN lv_up RESULTS DATA(lt_r3) ##REGEX_POSIX.
      LOOP AT lt_r3 INTO DATA(ls_r3).
        DATA(ls_sub3) = ls_r3-submatches[ 1 ].
        APPEND CONV sobj_name( lv_up+ls_sub3-offset(ls_sub3-length) ) TO lt_cls.
      ENDLOOP.

      FIND ALL OCCURRENCES OF REGEX
        `\b(?:REF\s+TO|NEW)\s+([A-Z/][A-Z0-9_/]{2,29})\b`
        IN lv_up RESULTS DATA(lt_r4) ##REGEX_POSIX.
      LOOP AT lt_r4 INTO DATA(ls_r4).
        DATA(ls_sub4) = ls_r4-submatches[ 1 ].
        APPEND CONV sobj_name( lv_up+ls_sub4-offset(ls_sub4-length) ) TO lt_cls.
      ENDLOOP.

*     Dynamically used objects. A structure that only appears as a
*     literal - MOVE 'ZBLE_S0211' TO lv_structure, handed to an ALV field
*     catalogue - has no static reference anywhere. No index holds it,
*     and the where-used list of the workbench does not know it either.
*     The literal is the only trace there is.
*
*     Every literal that could be an object name is collected and checked
*     against the catalogue below. A name with a blank in it cannot match
*     the pattern, so ordinary text literals fall away by themselves.
      FIND ALL OCCURRENCES OF REGEX `'([A-Z][A-Z0-9_/]{2,29})'`
        IN lv_up RESULTS DATA(lt_r5) ##REGEX_POSIX.
      LOOP AT lt_r5 INTO DATA(ls_r5).
        DATA(ls_sub5) = ls_r5-submatches[ 1 ].
        APPEND CONV sobj_name( lv_up+ls_sub5-offset(ls_sub5-length) ) TO lt_lit.
      ENDLOOP.

*     Message classes. They stand in no cross-reference index, and the
*     two forms that matter are not quoted, so the literal scan above
*     misses them: the MESSAGE-ID addition of the program header, and
*     the class in parentheses behind the message number. Without the
*     class the imported report shows the bare key - S:ZBLE_0001:006 -
*     instead of the text.
      FIND ALL OCCURRENCES OF REGEX `MESSAGE-ID\s+([A-Z0-9_/]+)`
        IN lv_up RESULTS DATA(lt_r6) ##REGEX_POSIX.
      LOOP AT lt_r6 INTO DATA(ls_r6).
        DATA(ls_sub6) = ls_r6-submatches[ 1 ].
        APPEND CONV sobj_name( lv_up+ls_sub6-offset(ls_sub6-length) ) TO lt_msg.
      ENDLOOP.

      FIND ALL OCCURRENCES OF REGEX `MESSAGE\s+[A-Z]?\d{3}\(([A-Z0-9_/]+)\)`
        IN lv_up RESULTS DATA(lt_r7) ##REGEX_POSIX.
      LOOP AT lt_r7 INTO DATA(ls_r7).
        DATA(ls_sub7) = ls_r7-submatches[ 1 ].
        APPEND CONV sobj_name( lv_up+ls_sub7-offset(ls_sub7-length) ) TO lt_msg.
      ENDLOOP.

    ENDLOOP.

    SORT lt_msg. DELETE ADJACENT DUPLICATES FROM lt_msg.
    IF lt_msg IS NOT INITIAL.
      SELECT arbgb FROM t100a
        FOR ALL ENTRIES IN @lt_msg
        WHERE arbgb = @lt_msg-table_line
        INTO TABLE @DATA(lt_mok).
      LOOP AT lt_mok INTO DATA(ls_mok).
        CLEAR ls_ref.
        ls_ref-type = 'MSAG'.
        ls_ref-name = ls_mok-arbgb.
        ls_ref-kind = lcl_t=>t( d = 'Nachrichtenklasse' e = 'message class' ).
        APPEND ls_ref TO rt_ref.
      ENDLOOP.
    ENDIF.

*   Function modules against TFDIR, the rest against the object catalog.
*   One query per kind instead of one per hit.
    SORT lt_fun. DELETE ADJACENT DUPLICATES FROM lt_fun.
    IF lt_fun IS NOT INITIAL.
      SELECT funcname FROM tfdir
        FOR ALL ENTRIES IN @lt_fun
        WHERE funcname = @lt_fun-table_line
        INTO TABLE @DATA(lt_fok).
      LOOP AT lt_fok INTO DATA(ls_fok).
        CLEAR ls_ref.
        ls_ref-type = 'FUNC'.
        ls_ref-name = ls_fok-funcname.
        ls_ref-kind = lcl_t=>t( d = 'Funktionsbaustein' e = 'function module' ).
        APPEND ls_ref TO rt_ref.
      ENDLOOP.
    ENDIF.

    SORT lt_tab. DELETE ADJACENT DUPLICATES FROM lt_tab.
    IF lt_tab IS NOT INITIAL.
      SELECT object, obj_name FROM tadir
        FOR ALL ENTRIES IN @lt_tab
        WHERE pgmid = 'R3TR' AND delflag = @abap_false AND object IN ( 'TABL', 'VIEW' )
          AND obj_name = @lt_tab-table_line
        INTO TABLE @DATA(lt_tok).
      LOOP AT lt_tok INTO DATA(ls_tok).
        CLEAR ls_ref.
        ls_ref-type = ls_tok-object.
        ls_ref-name = ls_tok-obj_name.
        ls_ref-kind = lcl_t=>t( d = 'Tabellenzugriff' e = 'table access' ).
        APPEND ls_ref TO rt_ref.
      ENDLOOP.
    ENDIF.

    SORT lt_cls. DELETE ADJACENT DUPLICATES FROM lt_cls.
    IF lt_cls IS NOT INITIAL.
      SELECT object, obj_name FROM tadir
        FOR ALL ENTRIES IN @lt_cls
        WHERE pgmid = 'R3TR' AND delflag = @abap_false AND object IN ( 'CLAS', 'INTF' )
          AND obj_name = @lt_cls-table_line
        INTO TABLE @DATA(lt_cok).
      LOOP AT lt_cok INTO DATA(ls_cok).
        CLEAR ls_ref.
        ls_ref-type = ls_cok-object.
        ls_ref-name = ls_cok-obj_name.
        ls_ref-kind = lcl_t=>t( d = 'Klassenverwendung' e = 'class used' ).
        APPEND ls_ref TO rt_ref.
      ENDLOOP.
    ENDIF.

*   The literals last, so that a name found statically keeps its more
*   precise label - the duplicate removal below keeps the first entry.
    SORT lt_lit. DELETE ADJACENT DUPLICATES FROM lt_lit.
    IF lt_lit IS NOT INITIAL.
      SELECT object, obj_name FROM tadir
        FOR ALL ENTRIES IN @lt_lit
        WHERE pgmid = 'R3TR' AND delflag = @abap_false
          AND object IN ( 'TABL', 'VIEW', 'DDLS', 'CLAS', 'INTF',
                          'PROG', 'DOMA', 'DTEL', 'FUGR' )
          AND obj_name = @lt_lit-table_line
        INTO TABLE @DATA(lt_lok).
      LOOP AT lt_lok INTO DATA(ls_lok).
        CLEAR ls_ref.
        ls_ref-type = ls_lok-object.
        ls_ref-name = ls_lok-obj_name.
        ls_ref-kind = lcl_t=>t( d = 'dynamisch verwendet' e = 'used dynamically' ).
        APPEND ls_ref TO rt_ref.
      ENDLOOP.
    ENDIF.

    DELETE rt_ref WHERE name = iv_name AND type = iv_type.
    SORT rt_ref BY type name.
    DELETE ADJACENT DUPLICATES FROM rt_ref COMPARING type name.
  ENDMETHOD.

  METHOD collect_refs.
*   Everything the object consumes, as far as the system can tell: the
*   indexed references from WBCROSSGT, the function modules and reports
*   from the source, and for DDIC objects the elements they are built from.
    DATA ls_ref TYPE ty_objref.
    DATA lv_max TYPE i.

    lv_max = mv_maxuse.
    IF lv_max <= 0.
      lv_max = 1000.
    ENDIF.

    DATA(lv_like) = |{ cross_prefix( iv_type = iv_type iv_name = iv_name ) }%|.
    IF lv_like <> '%'.
      DATA lt_one TYPE STANDARD TABLE OF wbcrossgt.
      SELECT * FROM wbcrossgt
        WHERE otype IN ( 'ME', 'TY' ) AND include LIKE @lv_like
        INTO TABLE @lt_one
        UP TO @lv_max ROWS.

*     The catalog is asked once for all names at a time. One SELECT SINGLE
*     per reference would be several hundred round trips per object.
      DATA lt_name TYPE STANDARD TABLE OF sobj_name.
      LOOP AT lt_one INTO DATA(ls_gt).
        DATA(lv_base) = base_name( CONV string( ls_gt-name ) ).
        IF lv_base IS NOT INITIAL.
          APPEND lv_base TO lt_name.
        ENDIF.
      ENDLOOP.
      SORT lt_name.
      DELETE ADJACENT DUPLICATES FROM lt_name.

      IF lt_name IS NOT INITIAL.
        SELECT object, obj_name FROM tadir
          FOR ALL ENTRIES IN @lt_name
          WHERE pgmid = 'R3TR' AND delflag = @abap_false
            AND object IN ( 'CLAS', 'INTF', 'TABL', 'VIEW', 'DTEL', 'DOMA',
                            'TTYP', 'DDLS', 'PROG', 'FUGR', 'MSAG', 'SHLP',
                            'ENQU', 'BDEF', 'SRVD', 'SRVB', 'DDLX', 'IDOC', 'WAPA' )
            AND obj_name = @lt_name-table_line
          INTO TABLE @DATA(lt_cat).
        LOOP AT lt_cat INTO DATA(ls_cat).
          APPEND VALUE #( type = ls_cat-object
                          name = ls_cat-obj_name ) TO rt_ref.
        ENDLOOP.
      ENDIF.
    ENDIF.

    APPEND LINES OF scan_source_calls( iv_type = iv_type
                                       iv_name = iv_name ) TO rt_ref.

*   Data elements of a table or structure, and the domain of a data
*   element - the chain the user actually wants to read through.
*
*   No limit here, and that is deliberate. P_MAXUSE caps the where-used
*   list, where the number of hits is open-ended. What a structure is
*   built from is not a usage but its composition: it is bounded by the
*   number of fields, and cutting it produces a document that cannot be
*   imported - one data element short, and the structure does not
*   activate. It cost a structure with 53 distinct data elements against
*   a limit of 50 to find that out, and which three fell away was up to
*   the database, since a SELECT without ORDER BY has no order to speak
*   of.
    IF iv_type = 'TABL' OR iv_type = 'VIEW'.
      DATA lv_tab TYPE dd03l-tabname.
      DATA lv_sg2 TYPE edisegment-segtyp.

      lv_tab = iv_name.

*     Bei einem IDoc-Segment steht in DD03L kein Datenelement - die
*     erzeugte Struktur ist eine flache Zeichenstruktur. Wer hier nur
*     DD03L fragt, nimmt kein einziges Datenelement mit, und im
*     Zielsystem scheitert SEGMENT_CREATE an Feldern, deren Datenelement
*     es dort nicht gibt. Dieselbe Falle wie bei der Feldliste.
      lv_sg2 = iv_name.
      SELECT COUNT(*) FROM edisegment WHERE segtyp = @lv_sg2.
      DATA(lv_isg2) = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).

      IF lv_isg2 = abap_true.
        SELECT DISTINCT rollname FROM edsappl
          WHERE segtyp = @lv_sg2 AND rollname <> ''
          INTO TABLE @DATA(lt_srol).
        LOOP AT lt_srol INTO DATA(ls_srol).
          APPEND VALUE #( type = 'DTEL' name = ls_srol-rollname ) TO rt_ref.
        ENDLOOP.
      ELSE.
        SELECT DISTINCT rollname FROM dd03l
          WHERE tabname = @lv_tab AND as4local = 'A' AND rollname <> ''
          INTO TABLE @DATA(lt_rol).
        LOOP AT lt_rol INTO DATA(ls_rol).
          APPEND VALUE #( type = 'DTEL' name = ls_rol-rollname ) TO rt_ref.
        ENDLOOP.
      ENDIF.
    ENDIF.

*   The includes of a program. INCLUDE ZBBC_ZAI0003. is a static
*   reference, but it is in no cross-reference index and matches none of
*   the usage patterns - and without the include the program does not
*   compile. Composition again, so no limit.
*
*   Read from the source, not from RS_GET_ALL_INCLUDES. That function
*   answers from D010INC, which is filled when the program is generated;
*   a program that has been transported but not yet run reports no
*   includes at all. D010INC also lists the generated units of every
*   class the program uses, which are includes to the compiler and to
*   nobody else. The source has neither problem.
    IF iv_type = 'PROG'.
      DATA lv_pmain TYPE syrepid.
      lv_pmain = iv_name.
      DATA(lv_psrc) = report_source( lv_pmain ).
      IF lv_psrc IS NOT INITIAL.
*       INCLUDE TYPE and INCLUDE STRUCTURE are something else entirely -
*       they add components to a structure definition. The optional
*       IF FOUND and the trailing period are not part of the name.
        FIND ALL OCCURRENCES OF REGEX
             `^\s*INCLUDE\s+(?!TYPE\b|STRUCTURE\b)([A-Za-z][\w/]*)`
             IN lv_psrc IGNORING CASE RESULTS DATA(lt_pinc) ##REGEX_POSIX.
        LOOP AT lt_pinc INTO DATA(ls_pinc).
          READ TABLE ls_pinc-submatches INTO DATA(ls_psub) INDEX 1.
          IF sy-subrc <> 0.
            CONTINUE.
          ENDIF.
          DATA(lv_pi) = to_upper( substring( val = lv_psrc
                                             off = ls_psub-offset
                                             len = ls_psub-length ) ).
          APPEND VALUE #( type = 'PROG' name = lv_pi ) TO rt_ref.
        ENDLOOP.
      ENDIF.
    ENDIF.

    IF iv_type = 'DTEL'.
      DATA lv_rol2 TYPE dd04l-rollname.
      lv_rol2 = iv_name.
      SELECT SINGLE domname FROM dd04l
        WHERE rollname = @lv_rol2 AND as4local = 'A'
        INTO @DATA(lv_dom).
      IF sy-subrc = 0 AND lv_dom IS NOT INITIAL.
        APPEND VALUE #( type = 'DOMA' name = lv_dom ) TO rt_ref.
      ENDIF.
    ENDIF.

    IF iv_type = 'DDLS'.
      DATA lv_ddl2 TYPE ddldependency-ddlname.
      lv_ddl2 = iv_name.
*     Also composition, not usage - no limit, see above.
      SELECT objectname FROM ddldependency
        WHERE ddlname = @lv_ddl2 AND state = 'A' AND objectname <> @lv_ddl2
        INTO TABLE @DATA(lt_dep).
      LOOP AT lt_dep INTO DATA(ls_dep).
        DATA(ls_res2) = resolve_repo_object( CONV string( ls_dep-objectname ) ).
        IF ls_res2-name IS NOT INITIAL.
          APPEND ls_res2 TO rt_ref.
        ENDIF.
      ENDLOOP.
    ENDIF.

*   A function module belongs to its group; without the group the reader
*   has no idea where it lives.
    IF iv_type = 'FUNC'.
      DATA(lv_grp) = func_group( CONV rs38l_fnam( iv_name ) ).
      IF lv_grp IS NOT INITIAL.
        APPEND VALUE #( type = 'FUGR' name = lv_grp ) TO rt_ref.
      ENDIF.
    ENDIF.

*   Der Pflegedialog. Auf den TVDIR-Eintrag zeigt kein Querverweis: die
*   Funktionsgruppe mit den Bildern und die Pflegetransaktion stehen
*   nur dort. Ohne sie kommt drueben ein View an, den SM30 nicht kennt.
    IF iv_type = 'TABL' OR iv_type = 'VIEW'.
      DATA lv_mtab TYPE tvdir-tabname.
      lv_mtab = iv_name.
      SELECT SINGLE area, cltcode FROM tvdir
        WHERE tabname = @lv_mtab INTO @DATA(ls_tvd).
      IF sy-subrc = 0.
        IF ls_tvd-area IS NOT INITIAL.
          APPEND VALUE #( type = 'FUGR' name = ls_tvd-area ) TO rt_ref.
        ENDIF.
        IF ls_tvd-cltcode IS NOT INITIAL.
          APPEND VALUE #( type = 'TRAN' name = ls_tvd-cltcode ) TO rt_ref.
        ENDIF.
      ENDIF.
    ENDIF.

*   Ein Basistyp besteht aus seinen Segmenttypen. Die Hierarchie steht
*   in der Syntaxtabelle und in keinem Querverweisindex - ohne diesen
*   Umweg kaeme im Zielsystem ein Basistyp an, dessen Segmente es nicht
*   gibt, und IDOCTYPE_CREATE lehnt ihn ab.
*
*   Angehaengt wird TABL, nicht SEGM: ein Segment traegt im Katalog TABL,
*   und die Definitionsermittlung erkennt es dort. So laeuft es durch
*   dieselben Wege wie jedes andere Objekt - Kurztext, Existenzpruefung,
*   Nachpruefung - und zieht ueber seine Struktur die Datenelemente
*   selbst nach.
    IF iv_type = 'IDOC'.
      DATA lv_ityp TYPE edi_iapi00-idoctyp.
      DATA ls_iatt TYPE edi_iapi01.
      DATA lt_isyn TYPE STANDARD TABLE OF edi_iapi02 WITH EMPTY KEY.

      lv_ityp = iv_name.
      CALL FUNCTION 'IDOCTYPE_READ'
        EXPORTING  pi_idoctyp         = lv_ityp
                   pi_check_authority = abap_true
        IMPORTING  pe_attributes      = ls_iatt
        TABLES     pt_syntax          = lt_isyn
        EXCEPTIONS object_not_found   = 1
                   no_authority       = 2
                   db_error           = 3
                   OTHERS             = 4.
      IF sy-subrc = 0.
        LOOP AT lt_isyn INTO DATA(ls_isyn).
          IF ls_isyn-segtyp IS NOT INITIAL.
            APPEND VALUE #( type = 'TABL' name = ls_isyn-segtyp ) TO rt_ref.
          ENDIF.
        ENDLOOP.
      ENDIF.
    ENDIF.

*   Eine Transaktion steht auf dem, was sie aufruft: bei der
*   Dialogtransaktion das Programm, bei der Parametertransaktion die
*   gerufene Transaktion.
    IF iv_type = 'TRAN'.
      DATA lv_rtc TYPE tstc-tcode.
      lv_rtc = iv_name.
      SELECT SINGLE pgmna FROM tstc WHERE tcode = @lv_rtc INTO @DATA(lv_pgm).
      IF sy-subrc = 0 AND lv_pgm IS NOT INITIAL.
        DATA(ls_rres) = resolve_repo_object( CONV string( lv_pgm ) ).
        IF ls_rres-name IS NOT INITIAL.
          APPEND ls_rres TO rt_ref.
        ENDIF.
      ENDIF.
    ENDIF.

    DELETE rt_ref WHERE name = iv_name AND type = iv_type.
    DELETE rt_ref WHERE name IS INITIAL.
    SORT rt_ref BY type name.
    DELETE ADJACENT DUPLICATES FROM rt_ref COMPARING type name.
    drop_sap( CHANGING ct_ref = rt_ref ).
  ENDMETHOD.

  METHOD document_object.

    DATA lv_short TYPE string.

    IF iv_type = 'FUNC'.
      SELECT SINGLE stext FROM tftit
        WHERE spras = @mv_langu AND funcname = @iv_name
        INTO @DATA(lv_ft).
      IF sy-subrc <> 0 AND mv_falb = abap_true.
        SELECT SINGLE stext FROM tftit
          WHERE spras = @mv_flang AND funcname = @iv_name
          INTO @lv_ft.
      ENDIF.
      lv_short = lv_ft.
    ELSE.
      lv_short = read_short_text( iv_type = iv_type iv_name = iv_name ).
    ENDIF.

    ro_chapter = NEW lcl_chapter(
      iv_id    = iv_id
      iv_level = iv_level
      iv_type  = 'OBJECT'
      iv_title = build_title( iv_name = CONV string( iv_name )
                              iv_text = lv_short ) ).

    DATA lv_pack TYPE devclass.
    DATA lv_auth TYPE responsibl.
    IF iv_type = 'FUNC'.
      DATA(lv_g) = func_group( CONV rs38l_fnam( iv_name ) ).
      SELECT SINGLE devclass, author FROM tadir
        WHERE pgmid = 'R3TR' AND delflag = @abap_false AND object = 'FUGR' AND obj_name = @lv_g
        INTO ( @lv_pack, @lv_auth ).
    ELSE.
      SELECT SINGLE devclass, author FROM tadir
        WHERE pgmid = 'R3TR' AND delflag = @abap_false AND object = @iv_type AND obj_name = @iv_name
        INTO ( @lv_pack, @lv_auth ).
    ENDIF.

    ro_chapter->set_reference( VALUE ty_reference(
      activity = CONV string( iv_type )
      docu_id  = CONV string( lv_auth )
      tcode    = CONV string( lv_pack ) ) ).

    IF mv_doku = abap_true.
      DATA(lv_docu) = read_docu( iv_type = iv_type iv_name = iv_name ).
      IF lv_docu IS NOT INITIAL.
        ro_chapter->set_documentation( lv_docu ).
        ro_chapter->set_doclang( CONV string( mv_last_lang ) ).
        mv_n_docu = mv_n_docu + 1.
        IF mv_last_lang <> mv_langu.
          mv_n_falb = mv_n_falb + 1.
        ENDIF.
      ENDIF.
    ENDIF.

    IF mv_detail = abap_true.
      add_details( iv_type = iv_type iv_name = iv_name io_chapter = ro_chapter ).
    ENDIF.

*   Normalerweise nur fuer das Objekt, nach dem gefragt wurde. Die Frage
*   "wer benutzt das" gilt dem Einstieg, nicht seiner Nachbarschaft - ein
*   Datenelement wie CHAR255 haengt an tausenden SAP-Programmen und
*   begruebe das Dokument unter seiner eigenen Liste.
*
*   Es gibt aber Faelle, in denen die Nachbarschaft die eigentliche Frage
*   ist: bei einem IDoc-Basistyp will man wissen, wer seine Segmente
*   liest, nicht wer den Basistyp typisiert - den typisiert niemand.
*   Dafuer das Kennzeichen; die Vorgabe bleibt beim Startobjekt.
    IF mv_used = abap_true
       AND ( iv_root = abap_true OR mv_useall = abap_true ).
      add_usages( iv_type = iv_type iv_name = iv_name io_chapter = ro_chapter ).
    ENDIF.

*   The call list costs a scan of WBCROSSGT plus the source; it is only
*   drawn for objects whose references were actually followed. For the
*   leaves of the tree the list would be dead weight anyway.
    IF mv_calls = abap_true AND iv_calls = abap_true.
      add_calls( iv_type = iv_type iv_name = iv_name io_chapter = ro_chapter ).
    ENDIF.

    IF mv_src = abap_true.
      DATA(lv_source) = read_source( iv_type = iv_type iv_name = iv_name ).
      IF lv_source IS NOT INITIAL.
        ro_chapter->set_source( lv_source ).
        mv_n_src = mv_n_src + 1.
      ENDIF.
    ENDIF.

    IF mv_def = abap_true.
      add_definition( iv_type = iv_type iv_name = iv_name io_chapter = ro_chapter ).
    ENDIF.

  ENDMETHOD.

  METHOD collect_single.

*   Die ersten Kapitel sind die Objekte, nach denen gefragt wurde -
*   eines bei einem einzelnen Startpunkt, mehrere bei einer
*   Arbeitsliste. Was sie verwenden, folgt danach in einem gemeinsamen
*   Kapitel, gruppiert nach Objekttyp: der Leser bekommt erst den
*   Einstieg und dann die Umgebung.
*
*   Die Kapitelnummern sind deshalb keine Konstanten mehr. Bei einem
*   Startobjekt kommt genau die alte Gliederung 1 / 2 / 3 heraus.
    DATA lt_start TYPE ty_objrefs.

    IF mt_start IS NOT INITIAL.
      lt_start = mt_start.
    ELSE.
      DATA(ls_one) = start_object( ).
      APPEND VALUE #( type = ls_one-type name = ls_one-name ) TO lt_start.
    ENDIF.

    DATA lt_queue TYPE ty_objrefs.
    DATA lt_done  TYPE ty_objrefs.
    DATA lt_open  TYPE ty_objrefs.
    DATA lv_depth TYPE i.
    DATA lv_sno   TYPE i.

    LOOP AT lt_start INTO DATA(ls_start).

      READ TABLE lt_done TRANSPORTING NO FIELDS
           WITH KEY type = ls_start-type name = ls_start-name.
      IF sy-subrc = 0.
        CONTINUE.
      ENDIF.

      lv_sno   = lv_sno + 1.
      mv_n_tot = mv_n_tot + 1.
      mv_n_obj = mv_n_obj + 1.

      co_document->add_chapter( document_object( iv_type  = ls_start-type
                                                 iv_name  = ls_start-name
                                                 iv_id    = |{ lv_sno }|
                                                 iv_level = 1
                                                 iv_calls = abap_true
                                                 iv_root  = abap_true ) ).

      APPEND VALUE #( type = ls_start-type name = ls_start-name ) TO lt_done.

*     Breadth first, so that the direct neighbours of the start objects
*     are documented before anything further out.
      IF mv_calls = abap_true AND mv_rdep > 0.
        APPEND LINES OF collect_refs( iv_type = ls_start-type
                                      iv_name = ls_start-name ) TO lt_queue.
      ENDIF.

    ENDLOOP.

    IF lv_sno = 0.
      RETURN.
    ENDIF.

    DATA lv_gref TYPE i.
    DATA lv_guse TYPE i.
    lv_gref = lv_sno + 1.
    lv_guse = lv_sno + 2.

    DATA(lo_refchap) = NEW lcl_chapter(
      iv_id    = |{ lv_gref }|
      iv_level = 1
      iv_type  = 'GROUP'
      iv_title = lcl_t=>t( d = 'Verwendete Objekte'
                           e = 'Objects used' ) ).

    DATA lt_all TYPE ty_objrefs.

*   Die beiden Richtungen sind unabhaengig voneinander schaltbar: die
*   verwendeten Objekte haengen an "Ausgehende Aufrufe" und der
*   Verweistiefe, die verwendenden an "Verwendungsnachweis" und der
*   Verwendungstiefe.
    lv_depth = 1.

    WHILE lt_queue IS NOT INITIAL AND lv_depth <= mv_rdep.

      CLEAR lt_open.

      LOOP AT lt_queue INTO DATA(ls_q).
        READ TABLE lt_done TRANSPORTING NO FIELDS
             WITH KEY type = ls_q-type name = ls_q-name.
        IF sy-subrc = 0.
          CONTINUE.
        ENDIF.
        ls_q-deep = boolc( lv_depth < mv_rdep ).
        APPEND ls_q TO lt_done.
        APPEND ls_q TO lt_all.
        APPEND ls_q TO lt_open.
      ENDLOOP.

      CLEAR lt_queue.
      lv_depth = lv_depth + 1.
      IF lv_depth > mv_rdep.
        EXIT.
      ENDIF.

      LOOP AT lt_open INTO DATA(ls_o).
        APPEND LINES OF collect_refs( iv_type = ls_o-type
                                      iv_name = ls_o-name ) TO lt_queue.
      ENDLOOP.

    ENDWHILE.

*   Kapitel 3: die Gegenrichtung. Wer das Startobjekt verwendet, wird bis
*   zur eingestellten Tiefe ebenfalls dokumentiert.
    DATA lt_users TYPE ty_objrefs.

    IF mv_used = abap_true AND mv_udep > 0.

      DATA lt_uq   TYPE ty_objrefs.
      DATA lt_uo   TYPE ty_objrefs.
      DATA lv_ud   TYPE i.

      LOOP AT lt_start INTO DATA(ls_su).
        APPEND LINES OF usage_objects( iv_type = ls_su-type
                                       iv_name = ls_su-name ) TO lt_uq.
      ENDLOOP.
      lv_ud = 1.

      WHILE lt_uq IS NOT INITIAL AND lv_ud <= mv_udep.

        CLEAR lt_uo.
        LOOP AT lt_uq INTO DATA(ls_u).
          READ TABLE lt_done TRANSPORTING NO FIELDS
               WITH KEY type = ls_u-type name = ls_u-name.
          IF sy-subrc = 0.
            CONTINUE.
          ENDIF.
          APPEND ls_u TO lt_done.
          APPEND ls_u TO lt_users.
          APPEND ls_u TO lt_uo.
        ENDLOOP.

        CLEAR lt_uq.
        lv_ud = lv_ud + 1.
        IF lv_ud > mv_udep.
          EXIT.
        ENDIF.

        LOOP AT lt_uo INTO DATA(ls_u2).
          APPEND LINES OF usage_objects( iv_type = ls_u2-type
                                         iv_name = ls_u2-name ) TO lt_uq.
        ENDLOOP.

      ENDWHILE.

    ENDIF.

    IF lt_all IS INITIAL AND lt_users IS INITIAL.
      RETURN.
    ENDIF.

    IF lt_all IS NOT INITIAL.
      co_document->add_chapter( lo_refchap ).
    ENDIF.

    SORT lt_all BY type name.

    DATA lv_last TYPE trobjtype.
    DATA lo_tchap TYPE REF TO lcl_chapter.
    DATA lv_tno TYPE i.
    DATA lv_ono TYPE i.

    LOOP AT lt_all INTO DATA(ls_a).

      mv_n_tot = mv_n_tot + 1.

      IF mv_maxobj > 0 AND mv_n_obj >= mv_maxobj.
        cv_trunc = abap_true.
        CONTINUE.
      ENDIF.

      IF s_objtyp[] IS NOT INITIAL AND ls_a-type NOT IN s_objtyp.
        CONTINUE.
      ENDIF.
      IF s_objnam[] IS NOT INITIAL AND ls_a-name NOT IN s_objnam.
        CONTINUE.
      ENDIF.

      IF ls_a-type <> lv_last.
        lv_last = ls_a-type.
        lv_tno = lv_tno + 1.
        lv_ono = 0.
        lo_tchap = NEW lcl_chapter( iv_id    = |{ lv_gref }.{ lv_tno }|
                                    iv_level = 2
                                    iv_type  = 'GROUP'
                                    iv_title = type_title( ls_a-type ) ).
        lo_refchap->add_child( lo_tchap ).
      ENDIF.

      lv_ono = lv_ono + 1.
      mv_n_obj = mv_n_obj + 1.

      lo_tchap->add_child( document_object( iv_type  = ls_a-type
                                            iv_name  = ls_a-name
                                            iv_id    = |{ lv_gref }.{ lv_tno }.{ lv_ono }|
                                            iv_level = 3
                                            iv_calls = ls_a-deep ) ).

    ENDLOOP.

*   Kapitel 3: die verwendenden Objekte, gleiche Gliederung wie Kapitel 2.
    IF lt_users IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lo_usechap) = NEW lcl_chapter(
      iv_id    = |{ lv_guse }|
      iv_level = 1
      iv_type  = 'GROUP'
      iv_title = lcl_t=>t( d = 'Verwendende Objekte'
                           e = 'Objects using this' ) ).
    co_document->add_chapter( lo_usechap ).

    SORT lt_users BY type name.

    CLEAR: lv_last, lo_tchap, lv_tno, lv_ono.

    LOOP AT lt_users INTO DATA(ls_us).

      mv_n_tot = mv_n_tot + 1.

      IF mv_maxobj > 0 AND mv_n_obj >= mv_maxobj.
        cv_trunc = abap_true.
        CONTINUE.
      ENDIF.

      IF s_objtyp[] IS NOT INITIAL AND ls_us-type NOT IN s_objtyp.
        CONTINUE.
      ENDIF.
      IF s_objnam[] IS NOT INITIAL AND ls_us-name NOT IN s_objnam.
        CONTINUE.
      ENDIF.

      IF ls_us-type <> lv_last.
        lv_last = ls_us-type.
        lv_tno = lv_tno + 1.
        lv_ono = 0.
        lo_tchap = NEW lcl_chapter( iv_id    = |{ lv_guse }.{ lv_tno }|
                                    iv_level = 2
                                    iv_type  = 'GROUP'
                                    iv_title = type_title( ls_us-type ) ).
        lo_usechap->add_child( lo_tchap ).
      ENDIF.

      lv_ono = lv_ono + 1.
      mv_n_obj = mv_n_obj + 1.

      lo_tchap->add_child( document_object( iv_type  = ls_us-type
                                            iv_name  = ls_us-name
                                            iv_id    = |{ lv_guse }.{ lv_tno }.{ lv_ono }|
                                            iv_level = 3 ) ).

    ENDLOOP.

  ENDMETHOD.

  METHOD lif_docu_collector~collect.

    DATA lt_packages TYPE cl_pak_package_queries=>tt_subpackage_info.
    DATA lt_tadir    TYPE cl_pak_package_queries=>tt_tadir_data.
    DATA lt_all      TYPE STANDARD TABLE OF devclass.
    DATA lv_trunc    TYPE abap_bool.
    DATA lv_cnt      TYPE i.

    ro_document = NEW lcl_document( ).

    IF mv_stype <> 'K'.
      collect_single( CHANGING co_document = ro_document
                               cv_trunc    = lv_trunc ).
      ro_document->set_meta( VALUE ty_meta(
        version    = gc_version
        doc_type   = 'DEV'
        system     = sy-sysid
        client     = sy-mandt
        created_by = sy-uname
        created_at = |{ sy-datum DATE = ISO } { sy-uzeit TIME = ISO }|
        language   = mv_langu
        truncated  = boolc( lv_trunc = abap_true OR mv_src_trunc = abap_true )
        node_limit = mv_maxobj
        node_total = mv_n_tot
        src_trunc  = mv_src_trunc
        src_limit  = mv_maxsrc ) ).
      RETURN.
    ENDIF.

    APPEND mv_pack TO lt_all.

    " Subpackages recursively - the API returns the complete subtree, a
    " descent of our own through TDEVC-PARENTCL is not necessary.
    " The methods work with classic exceptions. Without an EXCEPTIONS
    " clause in the call every one of them leads to a short dump -
    " TRY...CATCH does not help here because they are not class-based.
    " Packages without a TDEVC or TADIR record do occur in practice.
    IF mv_recur = abap_true.
      CALL METHOD cl_pak_package_queries=>get_all_subpackages
        EXPORTING
          im_package                    = mv_pack
          im_also_local_packages        = mv_local
        IMPORTING
          et_subpackages                = lt_packages
        EXCEPTIONS
          no_package_specified          = 1
          package_has_no_tdevc_record   = 2
          package_has_no_tadir_record   = 3
          package_does_not_exist        = 4
          invalid_superpackage          = 5
          no_output_parameter_requested = 6
          OTHERS                        = 7.
      IF sy-subrc = 0.
        LOOP AT lt_packages INTO DATA(ls_sub).
          APPEND ls_sub-package TO lt_all.
        ENDLOOP.
      ELSE.
        mv_note = |Unterpakete nicht ermittelbar: { pack_reason( sy-subrc ) }.|.
      ENDIF.
    ENDIF.

    SORT lt_all.
    DELETE ADJACENT DUPLICATES FROM lt_all.

    DATA lv_pno TYPE i.

    LOOP AT lt_all INTO DATA(lv_pack).

      lv_pno = lv_pno + 1.
      mv_n_pack = mv_n_pack + 1.

      DATA(lo_pchap) = NEW lcl_chapter(
        iv_id    = |{ lv_pno }|
        iv_level = 1
        iv_type  = 'PACKAGE'
        iv_title = build_title( iv_name = CONV string( lv_pack )
                                iv_text = read_short_text(
                                            iv_type = 'DEVC'
                                            iv_name = CONV sobj_name( lv_pack ) ) ) ).
      ro_document->add_chapter( lo_pchap ).

      CLEAR lt_tadir.
      CALL METHOD cl_pak_package_queries=>get_dev_object_tadir_keys
        EXPORTING
          im_package                    = lv_pack
          im_also_local_packages        = mv_local
        IMPORTING
          et_tadir_data                 = lt_tadir
        EXCEPTIONS
          no_package_specified          = 1
          package_has_no_tdevc_record   = 2
          package_has_no_tadir_record   = 3
          package_does_not_exist        = 4
          no_output_parameter_requested = 5
          OTHERS                        = 6.
      IF sy-subrc <> 0.
        " Package without a catalog entry - note it instead of aborting
        lo_pchap->set_documentation(
          |{ lcl_t=>t( d = `Objektliste nicht lesbar` e = `Object list cannot be read` ) }| &&
          |: { pack_reason( sy-subrc ) }.| ).
        CONTINUE.
      ENDIF.

      " Group the objects by type
      SORT lt_tadir BY object_type object_name.

*     Geloeschte Objekte bleiben in TADIR stehen, solange der Auftrag,
*     in dem sie geloescht wurden, nicht freigegeben ist - mit
*     DELFLAG = X. Der Paketbaustein liefert sie trotzdem mit. Ohne
*     diesen Filter erscheint im Dokument eine Klasse, die es im System
*     nicht mehr gibt.
      SELECT object, obj_name FROM tadir
        WHERE devclass = @lv_pack AND delflag = @abap_true
        INTO TABLE @DATA(lt_gone).

*     Eine CDS-View steht im Katalog zweimal: als DDL-Quelle (DDLS) mit
*     allem und als Strukturobjekt (STOB) mit nur Titel und Beschreibung.
*     Steht die DDL-Quelle im selben Export, traegt der STOB-Eintrag
*     nichts Eigenes bei. Er wird unterdrueckt - gleicher Gedanke wie der
*     Filter fuer geloeschte Objekte. Die Zuordnung STOB -> DDL-Quelle
*     steht in DDLDEPENDENCY; nur die tatsaechlich enthaltenen DDL-
*     Quellen zaehlen, deshalb dieselben Filter wie in der Hauptschleife.
      DATA lt_ddls TYPE SORTED TABLE OF ddlname WITH UNIQUE KEY table_line.
      CLEAR lt_ddls.
      LOOP AT lt_tadir INTO DATA(ls_ddl) WHERE object_type = 'DDLS'.
        IF s_objtyp[] IS NOT INITIAL AND ls_ddl-object_type NOT IN s_objtyp.
          CONTINUE.
        ENDIF.
        IF s_objnam[] IS NOT INITIAL AND ls_ddl-object_name NOT IN s_objnam.
          CONTINUE.
        ENDIF.
        IF lt_gone IS NOT INITIAL.
          READ TABLE lt_gone TRANSPORTING NO FIELDS
               WITH KEY object = 'DDLS' obj_name = ls_ddl-object_name.
          IF sy-subrc = 0.
            CONTINUE.
          ENDIF.
        ENDIF.
        INSERT ls_ddl-object_name INTO TABLE lt_ddls.
      ENDLOOP.

      DATA lv_last_type TYPE trobjtype.
      DATA lo_tchap TYPE REF TO lcl_chapter.
      DATA lv_tno TYPE i.
      DATA lv_ono TYPE i.
      CLEAR: lv_last_type, lo_tchap, lv_tno.

      LOOP AT lt_tadir INTO DATA(ls_tadir).

        IF ls_tadir-object_type = 'DEVC'.
          CONTINUE.
        ENDIF.

        IF s_objtyp[] IS NOT INITIAL AND ls_tadir-object_type NOT IN s_objtyp.
          CONTINUE.
        ENDIF.
        IF s_objnam[] IS NOT INITIAL AND ls_tadir-object_name NOT IN s_objnam.
          CONTINUE.
        ENDIF.

        IF lt_gone IS NOT INITIAL.
          READ TABLE lt_gone TRANSPORTING NO FIELDS
               WITH KEY object   = ls_tadir-object_type
                        obj_name = ls_tadir-object_name.
          IF sy-subrc = 0.
            CONTINUE.
          ENDIF.
        ENDIF.

*       STOB-Duplikat einer CDS-View unterdruecken, wenn ihre DDL-Quelle
*       im selben Export steht. Vor dem Zaehler, damit der leere Eintrag
*       auch nicht in node_total mitzaehlt.
        IF ls_tadir-object_type = 'STOB' AND lt_ddls IS NOT INITIAL.
          DATA lv_stob TYPE ddldependency-objectname.
          DATA lv_sddl TYPE ddldependency-ddlname.
          lv_stob = ls_tadir-object_name.
          CLEAR lv_sddl.
          SELECT SINGLE ddlname FROM ddldependency
            WHERE objectname = @lv_stob AND objecttype = 'STOB' AND state = 'A'
            INTO @lv_sddl.
          IF sy-subrc = 0 AND lv_sddl IS NOT INITIAL.
            READ TABLE lt_ddls TRANSPORTING NO FIELDS
                 WITH KEY table_line = lv_sddl.
            IF sy-subrc = 0.
              CONTINUE.
            ENDIF.
          ENDIF.
        ENDIF.

        mv_n_tot = mv_n_tot + 1.

        IF mv_maxobj > 0 AND mv_n_obj >= mv_maxobj.
          lv_trunc = abap_true.
          CONTINUE.
        ENDIF.

        IF ls_tadir-object_type <> lv_last_type.
          lv_last_type = ls_tadir-object_type.
          lv_tno = lv_tno + 1.
          lv_ono = 0.
          lo_tchap = NEW lcl_chapter( iv_id    = |{ lv_pno }.{ lv_tno }|
                                      iv_level = 2
                                      iv_type  = 'GROUP'
                                      iv_title = type_title( ls_tadir-object_type ) ).
          lo_pchap->add_child( lo_tchap ).
        ENDIF.

        lv_ono = lv_ono + 1.
        mv_n_obj = mv_n_obj + 1.

        DATA(lo_ochap) = NEW lcl_chapter(
          iv_id    = |{ lv_pno }.{ lv_tno }.{ lv_ono }|
          iv_level = 3
          iv_type  = 'OBJECT'
          iv_title = build_title( iv_name = CONV string( ls_tadir-object_name )
                                  iv_text = read_short_text(
                                              iv_type = ls_tadir-object_type
                                              iv_name = ls_tadir-object_name ) ) ).
        lo_tchap->add_child( lo_ochap ).

        lo_ochap->set_reference( VALUE ty_reference(
          activity = CONV string( ls_tadir-object_type )
          docu_id  = CONV string( ls_tadir-author )
          tcode    = CONV string( ls_tadir-package ) ) ).

        IF mv_doku = abap_true.
          DATA(lv_docu) = read_docu( iv_type = ls_tadir-object_type
                                     iv_name = ls_tadir-object_name ).
          IF lv_docu IS NOT INITIAL.
            lo_ochap->set_documentation( lv_docu ).
            lo_ochap->set_doclang( CONV string( mv_last_lang ) ).
            mv_n_docu = mv_n_docu + 1.
            IF mv_last_lang <> mv_langu.
              mv_n_falb = mv_n_falb + 1.
            ENDIF.
          ENDIF.
        ENDIF.

        IF mv_detail = abap_true.
          add_details( iv_type    = ls_tadir-object_type
                       iv_name    = ls_tadir-object_name
                       io_chapter = lo_ochap ).
        ENDIF.

        IF mv_used = abap_true.
          add_usages( iv_type    = ls_tadir-object_type
                      iv_name    = ls_tadir-object_name
                      io_chapter = lo_ochap ).
        ENDIF.

        IF mv_calls = abap_true.
          add_calls( iv_type    = ls_tadir-object_type
                     iv_name    = ls_tadir-object_name
                     io_chapter = lo_ochap ).
        ENDIF.

        IF mv_src = abap_true.
          DATA(lv_source) = read_source( iv_type = ls_tadir-object_type
                                         iv_name = ls_tadir-object_name ).
          IF lv_source IS NOT INITIAL.
            lo_ochap->set_source( lv_source ).
            mv_n_src = mv_n_src + 1.
          ENDIF.
        ENDIF.

*       Definitionsdaten auch im Paketlauf. Bisher entstanden sie nur im
*       Einzelobjektmodus (document_object); ein Paketexport trug trotz
*       angehakter Definitionsdaten keine einzige und liess sich nicht
*       importieren.
        IF mv_def = abap_true.
          add_definition( iv_type    = ls_tadir-object_type
                          iv_name    = ls_tadir-object_name
                          io_chapter = lo_ochap ).
        ENDIF.

      ENDLOOP.

    ENDLOOP.

    ro_document->set_meta( VALUE ty_meta(
      version    = gc_version
      doc_type   = 'DEV'
      system     = sy-sysid
      client     = sy-mandt
      created_by = sy-uname
      created_at = |{ sy-datum DATE = ISO } { sy-uzeit TIME = ISO }|
      language   = mv_langu
      truncated  = boolc( lv_trunc = abap_true OR mv_src_trunc = abap_true )
      node_limit = mv_maxobj
      node_total = mv_n_tot
      src_trunc  = mv_src_trunc
      src_limit  = mv_maxsrc ) ).

  ENDMETHOD.

  METHOD get_stat_packages.
    rv = mv_n_pack.
  ENDMETHOD.
  METHOD get_stat_objects.
    rv = mv_n_obj.
  ENDMETHOD.
  METHOD get_stat_total.
    rv = mv_n_tot.
  ENDMETHOD.
  METHOD get_stat_docu.
    rv = mv_n_docu.
  ENDMETHOD.
  METHOD get_stat_source.
    rv = mv_n_src.
  ENDMETHOD.
  METHOD get_stat_usage.
    rv = mv_n_use.
  ENDMETHOD.
  METHOD get_stat_fallback.
    rv = mv_n_falb.
  ENDMETHOD.
  METHOD get_stat_calls.
    rv = mv_n_call.
  ENDMETHOD.
  METHOD get_stat_def.
    rv = mv_n_def.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* Start point: type and value
*
* The type codes are the ones the Object Navigator uses, so the field
* reads the same way it does in SE80. Everything except K documents a
* single object; K keeps the package run the report started out with.
*----------------------------------------------------------------------*
FORM stype_list CHANGING ct_list TYPE ty_stypes.

  CLEAR ct_list.
  IF sy-langu = 'D'.
    ct_list = VALUE #(
      ( code = 'K'  text = 'Paket' )
      ( code = 'P'  text = 'Programm / Report' )
      ( code = 'C'  text = 'Klasse / Interface' )
      ( code = 'FF' text = 'Funktionsbaustein' )
      ( code = 'F'  text = 'Funktionsgruppe' )
      ( code = 'T'  text = 'Tabelle / Struktur' )
      ( code = 'V'  text = 'View' )
      ( code = 'D'  text = 'Datenelement' )
      ( code = 'DO' text = 'Domäne' )
      ( code = 'W'  text = 'CDS View' )
      ( code = 'MX' text = 'Metadata Extension' )
      ( code = 'BD' text = 'Verhaltensdefinition' )
      ( code = 'SD' text = 'Service-Definition' )
      ( code = 'SB' text = 'Service-Binding' )
      ( code = 'IS' text = 'IDoc-Segmenttyp' )
      ( code = 'IT' text = 'IDoc-Basistyp' )
      ( code = 'U5' text = 'UI5-Anwendung (BSP)' )
      ( code = 'SF' text = 'Smart Form' )
      ( code = 'AF' text = 'Adobe Form (Formular)' )
      ( code = 'AI' text = 'Adobe Form (Schnittstelle)' )
*     Kein Objekt, sondern eine Liste davon: die Fehlliste, die der
*     IMG-Report im Zielsystem geschrieben hat. Der Startpunkt steht
*     dann in der Datei, nicht im Namensfeld.
      ( code = 'AL' text = 'Arbeitsliste aus Fehlliste' ) ).
  ELSE.
    ct_list = VALUE #(
      ( code = 'K'  text = 'Package' )
      ( code = 'P'  text = 'Program / report' )
      ( code = 'C'  text = 'Class / interface' )
      ( code = 'FF' text = 'Function module' )
      ( code = 'F'  text = 'Function group' )
      ( code = 'T'  text = 'Table / structure' )
      ( code = 'V'  text = 'View' )
      ( code = 'D'  text = 'Data element' )
      ( code = 'DO' text = 'Domain' )
      ( code = 'W'  text = 'CDS view' )
      ( code = 'MX' text = 'Metadata extension' )
      ( code = 'BD' text = 'Behavior definition' )
      ( code = 'SD' text = 'Service definition' )
      ( code = 'SB' text = 'Service binding' )
      ( code = 'IS' text = 'IDoc segment type' )
      ( code = 'IT' text = 'IDoc basic type' )
      ( code = 'U5' text = 'UI5 application (BSP)' )
      ( code = 'SF' text = 'Smart Form' )
      ( code = 'AF' text = 'Adobe Form' )
      ( code = 'AI' text = 'Adobe Form interface' )
      ( code = 'AL' text = 'Work list from request list' ) ).
  ENDIF.

ENDFORM.

FORM stype_text USING iv_code TYPE char2
                CHANGING cv_text TYPE clike.

  DATA lt_list TYPE ty_stypes.
  PERFORM stype_list CHANGING lt_list.

  READ TABLE lt_list INTO DATA(ls_l) WITH KEY code = iv_code.
  IF sy-subrc = 0.
    cv_text = ls_l-text.
  ELSE.
    cv_text = lcl_t=>ui( d = `unbekannter Typ` e = `unknown type` ).
  ENDIF.

ENDFORM.

FORM check_stype.

  DATA lt_list TYPE ty_stypes.
  PERFORM stype_list CHANGING lt_list.

  READ TABLE lt_list TRANSPORTING NO FIELDS WITH KEY code = p_stype.
  IF sy-subrc <> 0.
    MESSAGE lcl_t=>ui( d = `Unbekannter Typ - F4 zeigt die moeglichen Werte.`
                       e = `Unknown type - F4 shows the possible values.` )
            TYPE 'E'.
  ENDIF.

ENDFORM.

FORM f4_stype.

  DATA lt_list TYPE ty_stypes.

  PERFORM stype_list CHANGING lt_list.

  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING
      retfield        = 'CODE'
      dynpprog        = sy-repid
      dynpnr          = sy-dynnr
      dynprofield     = 'P_STYPE'
      value_org       = 'S'
    TABLES
      value_tab       = lt_list
    EXCEPTIONS
      parameter_error = 1
      no_values_found = 2
      OTHERS          = 3.

ENDFORM.

FORM f4_sval.

*  The value help follows the type: a package is looked up in TDEVC, a
*  function module in TFDIR, everything else in the object catalog.
* Same rule as for the type list: dictionary types only, no string.
  TYPES: BEGIN OF ty_hit,
           name TYPE sobj_name,
           text TYPE ddtext,
         END OF ty_hit.

  DATA lt_hit  TYPE STANDARD TABLE OF ty_hit.
  DATA lv_like TYPE string.
  DATA lv_obj  TYPE tadir-object.

  lv_like = to_upper( condense( CONV string( p_sval ) ) ).
  IF lv_like IS INITIAL.
    lv_like = '%'.
  ELSE.
    lv_like = |{ lv_like }%|.
  ENDIF.

  CASE p_stype.

    WHEN 'K'.
      SELECT d~devclass AS name, t~ctext AS text
        FROM tdevc AS d
        LEFT OUTER JOIN tdevct AS t
          ON t~devclass = d~devclass AND t~spras = @sy-langu
        WHERE d~devclass LIKE @lv_like
        ORDER BY d~devclass
        INTO CORRESPONDING FIELDS OF TABLE @lt_hit
        UP TO 300 ROWS.

    WHEN 'FF'.
      SELECT f~funcname AS name, t~stext AS text
        FROM tfdir AS f
        LEFT OUTER JOIN tftit AS t
          ON t~funcname = f~funcname AND t~spras = @sy-langu
        WHERE f~funcname LIKE @lv_like
        ORDER BY f~funcname
        INTO CORRESPONDING FIELDS OF TABLE @lt_hit
        UP TO 300 ROWS.

    WHEN OTHERS.
      CASE p_stype.
        WHEN 'P'.  lv_obj = 'PROG'.
        WHEN 'C'.  lv_obj = 'CLAS'.
        WHEN 'F'.  lv_obj = 'FUGR'.
        WHEN 'T'.  lv_obj = 'TABL'.
        WHEN 'V'.  lv_obj = 'VIEW'.
        WHEN 'D'.  lv_obj = 'DTEL'.
        WHEN 'DO'. lv_obj = 'DOMA'.
        WHEN 'W'.  lv_obj = 'DDLS'.
        WHEN 'MX'. lv_obj = 'DDLX'.
        WHEN 'BD'. lv_obj = 'BDEF'.
        WHEN 'SD'. lv_obj = 'SRVD'.
        WHEN 'SB'. lv_obj = 'SRVB'.
        WHEN 'IS'. lv_obj = 'TABL'.
        WHEN 'IT'. lv_obj = 'IDOC'.
        WHEN 'U5'. lv_obj = 'WAPA'.
        WHEN 'SF'. lv_obj = 'SSFO'.
        WHEN 'AF'. lv_obj = 'SFPF'.
        WHEN 'AI'. lv_obj = 'SFPI'.
        WHEN OTHERS. lv_obj = 'PROG'.
      ENDCASE.
      SELECT obj_name AS name, devclass AS text
        FROM tadir
        WHERE pgmid = 'R3TR' AND object = @lv_obj
          AND obj_name LIKE @lv_like AND delflag = @abap_false
        ORDER BY obj_name
        INTO CORRESPONDING FIELDS OF TABLE @lt_hit
        UP TO 300 ROWS.

  ENDCASE.

  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING
      retfield        = 'NAME'
      dynpprog        = sy-repid
      dynpnr          = sy-dynnr
      dynprofield     = 'P_SVAL'
      value_org       = 'S'
    TABLES
      value_tab       = lt_hit
    EXCEPTIONS
      parameter_error = 1
      no_values_found = 2
      OTHERS          = 3.

ENDFORM.

*----------------------------------------------------------------------*
* Output helper routines
*----------------------------------------------------------------------*
*&---------------------------------------------------------------------*
*& FORM screen_mode
*&---------------------------------------------------------------------*
* Import and documentation are two runs on one screen. What the other
* one needs is switched inactive, and above all the start point loses
* its obligation - OBLIGATORY cannot be declared conditionally, but the
* required flag can be taken off in the PBO.
*----------------------------------------------------------------------*
FORM screen_mode.

  LOOP AT SCREEN.
    CASE screen-name.
      WHEN 'P_STYPE' OR 'P_SVAL'.
*       Only greyed out, never marked required. A required flag is
*       enforced by the runtime on the next round trip, and the next
*       round trip may well be the one that ticks the import flag.
        IF p_imp = abap_true.
          screen-input = 0.
        ELSE.
          screen-input = 1.
        ENDIF.
        MODIFY SCREEN.
      WHEN 'P_IFILE' OR 'P_ISRV' OR 'P_ITEST' OR 'P_IOVER'
        OR 'P_IACT' OR 'P_IPACK' OR 'P_ITR' OR 'P_IKEEP' OR 'P_ITASK'
        OR 'P_IREN'
        OR 'P_IOLD1' OR 'P_INEW1' OR 'P_IOLD2' OR 'P_INEW2'
        OR 'P_IOLD3' OR 'P_INEW3' OR 'P_IOLD4' OR 'P_INEW4'.
        IF p_imp = abap_true.
          screen-input = 1.
        ELSE.
          screen-input = 0.
        ENDIF.
        MODIFY SCREEN.
      WHEN 'P_XML'.
*       An "Definitionsdaten fuer Reimport" gekoppelt: dann erzwungen an
*       und nicht abwaehlbar.
        IF p_def = abap_true.
          screen-input = 0.
        ELSE.
          screen-input = 1.
        ENDIF.
        MODIFY SCREEN.
    ENDCASE.
  ENDLOOP.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM f4_ifile
*&---------------------------------------------------------------------*
* File dialog for the import file. Only for the PC path - a file on the
* application server cannot be browsed from the frontend.
*----------------------------------------------------------------------*
FORM f4_ifile.

  DATA lt_file TYPE filetable.
  DATA lv_rc   TYPE i.
  DATA lv_act  TYPE i.

  IF p_isrv = abap_true.
    MESSAGE lcl_t=>ui(
      d = `Die Datei liegt auf dem Applikationsserver - Pfad bitte eintippen (AL11).`
      e = `The file is on the application server - please type the path (AL11).` )
      TYPE 'S'.
    RETURN.
  ENDIF.

  cl_gui_frontend_services=>file_open_dialog(
    EXPORTING
      window_title      = lcl_t=>ui( d = `Documizer-XML auswaehlen`
                                     e = `Select Documizer XML` )
      default_extension = 'xml'
      multiselection    = abap_false
    CHANGING
      file_table        = lt_file
      rc                = lv_rc
      user_action       = lv_act
    EXCEPTIONS
      OTHERS            = 1 ).

  IF sy-subrc <> 0 OR lv_act <> cl_gui_frontend_services=>action_ok.
    RETURN.
  ENDIF.

  READ TABLE lt_file INTO DATA(ls_file) INDEX 1.
  IF sy-subrc = 0.
    p_ifile = ls_file-filename.
  ENDIF.

ENDFORM.

FORM f4_verzeichnis.

  DATA lv_dir TYPE string.

  cl_gui_frontend_services=>directory_browse(
    EXPORTING
      initial_folder  = CONV string( p_path )
    CHANGING
      selected_folder = lv_dir
    EXCEPTIONS
      OTHERS          = 1 ).

  IF lv_dir IS NOT INITIAL.
    p_path = lv_dir.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM ensure_task
*&---------------------------------------------------------------------*
FORM ensure_task.

* Ein Objekt landet nicht im Auftrag, sondern in einer Aufgabe darunter.
* Fehlt sie, meldet das Korrektursystem "No matching task exists under
* request ... for user ..." - und der Aufruf scheitert mit einer Nummer,
* die nach Berechtigungsproblem aussieht. Eine freigegebene Aufgabe
* zaehlt dabei nicht: sie nimmt nichts mehr auf.
  DATA ls_e070 TYPE e070.
  DATA lt_user TYPE STANDARD TABLE OF tr005 WITH EMPTY KEY.
  DATA lt_msg  TYPE STANDARD TABLE OF tr004 WITH EMPTY KEY.
  DATA lv_exc  TYPE tr007-exception.
  DATA lv_trk  TYPE tr001-strkorr.

  IF p_itr IS INITIAL.
    RETURN.
  ENDIF.

  SELECT SINGLE * FROM e070 WHERE trkorr = @p_itr INTO @ls_e070.
  IF sy-subrc <> 0.
    WRITE: / lcl_t=>ui( d = `Auftrag nicht gefunden           :`
                        e = `Request not found                :` ), p_itr.
    RETURN.
  ENDIF.

* Wer eine Aufgabe statt eines Auftrags eingetragen hat, ist schon fertig.
  IF ls_e070-strkorr IS NOT INITIAL.
    RETURN.
  ENDIF.

* D und L sind die aenderbaren Zustaende; alles andere ist freigegeben
* oder unterwegs.
  SELECT SINGLE trkorr FROM e070
    WHERE strkorr = @p_itr AND as4user = @sy-uname
      AND ( trstatus = 'D' OR trstatus = 'L' )
    INTO @DATA(lv_task).
  IF sy-subrc = 0.
    WRITE: / lcl_t=>ui( d = `Aufgabe                          :`
                        e = `Task                             :` ), lv_task.
    RETURN.
  ENDIF.

  IF p_itask = abap_false.
    WRITE: / lcl_t=>ui(
      d = `ACHTUNG: keine offene Aufgabe unter dem Auftrag - der Import wird scheitern.`
      e = `CAUTION: no open task under the request - the import will fail.` ).
    RETURN.
  ENDIF.

  APPEND VALUE tr005( as4user = sy-uname ) TO lt_user.
  lv_trk = p_itr.

  CALL FUNCTION 'TR40_TASK_ADD'
    EXPORTING iv_trkorr     = lv_trk
              iv_correction = abap_true
    IMPORTING ev_exception  = lv_exc
    TABLES    tt_userlist   = lt_user
              tt_msg        = lt_msg.

  READ TABLE lt_user INTO DATA(ls_user) INDEX 1.
  IF lv_exc IS INITIAL AND ls_user-correction IS NOT INITIAL.
    WRITE: / lcl_t=>ui( d = `Aufgabe angelegt                 :`
                        e = `Task created                     :` ), ls_user-correction.
  ELSE.
    WRITE: / lcl_t=>ui( d = `Aufgabe nicht anlegbar           :`
                        e = `Task could not be created        :` ), lv_exc.
    LOOP AT lt_msg INTO DATA(ls_msg).
      WRITE: / '  ', ls_msg-msgtext.
    ENDLOOP.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM suggest_fname
*&---------------------------------------------------------------------*
FORM suggest_fname.

* Der Vorschlag wird bei jedem Bildaufbau neu gebildet, damit er dem
* Startobjekt folgt: wer den Objektnamen aendert, sieht den Dateinamen
* sofort mitwandern. Ueberschrieben wird das Feld nur, solange darin
* noch der vorige Vorschlag steht - ein selbst gewaehlter Name bleibt.
  DATA lv_new  TYPE string.
  DATA lv_part TYPE string.

  PERFORM fname_object CHANGING lv_part.
  lv_new = |documizer_dev_{ sy-sysid }{ lv_part }_{ sy-datum }_{ sy-uzeit }|.

  IF p_fname IS INITIAL OR p_fname = gv_fauto.
    p_fname = lv_new.
  ENDIF.
  gv_fauto = lv_new.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM fname_object
*&---------------------------------------------------------------------*
FORM fname_object CHANGING cv_part TYPE string.

  CLEAR cv_part.

* Bei der Arbeitsliste gibt es kein einzelnes Startobjekt - der
* Startpunkt steht in der Datei, nicht im Namensfeld.
  IF p_stype = 'AL' OR p_sval IS INITIAL.
    RETURN.
  ENDIF.

* Ein Namensraum bringt Schraegstriche mit, und die trennen im
* Dateisystem Verzeichnisse. Aus /BOBF/OBJ wird _bobf_obj.
  DATA lv_name TYPE string.
  lv_name = to_lower( CONV string( p_sval ) ).
  REPLACE ALL OCCURRENCES OF `/` IN lv_name WITH `_`.
  REPLACE ALL OCCURRENCES OF `\` IN lv_name WITH `_`.
  REPLACE ALL OCCURRENCES OF ` ` IN lv_name WITH `_`.
  CONDENSE lv_name NO-GAPS.
  IF lv_name IS INITIAL.
    RETURN.
  ENDIF.

  cv_part = |_{ lv_name }|.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM file_base
*&---------------------------------------------------------------------*
FORM file_base CHANGING cv_base TYPE string.

* Im Hintergrund gibt es kein Selektionsbild, das den Vorschlag
* gefuellt haette, und ein per SUBMIT uebergebener leerer Name darf
* nicht zu einer Datei ohne Namen fuehren.
  DATA lv_part TYPE string.

  cv_base = p_fname.
  CONDENSE cv_base.
  IF cv_base IS INITIAL.
    PERFORM fname_object CHANGING lv_part.
    cv_base = |documizer_dev_{ sy-sysid }{ lv_part }_{ sy-datum }_{ sy-uzeit }|.
  ENDIF.

ENDFORM.

FORM download USING iv_content TYPE string
                    iv_ext     TYPE string.

  DATA lv_x    TYPE xstring.
  DATA lv_len  TYPE i.
  DATA lt_bin  TYPE solix_tab.
  DATA lv_file TYPE string.
  DATA lv_dir  TYPE string.
  DATA lv_base TYPE string.

  IF sy-batch = abap_true.
    WRITE: / lcl_t=>ui( d = `Download auf den PC im Hintergrund nicht möglich:` e = `PC download not possible in the background:` ), iv_ext.
    RETURN.
  ENDIF.

  lv_dir = p_path.
  CONDENSE lv_dir.
  IF lv_dir CA '\'.
    IF substring( val = lv_dir off = strlen( lv_dir ) - 1 len = 1 ) <> '\'.
      lv_dir = |{ lv_dir }\\|.
    ENDIF.
  ENDIF.

  PERFORM file_base CHANGING lv_base.
  lv_file = |{ lv_dir }{ lv_base }.{ iv_ext }|.
  lv_x = cl_abap_codepage=>convert_to( iv_content ).

  CALL FUNCTION 'SCMS_XSTRING_TO_BINARY'
    EXPORTING
      buffer        = lv_x
    IMPORTING
      output_length = lv_len
    TABLES
      binary_tab    = lt_bin.

  cl_gui_frontend_services=>gui_download(
    EXPORTING
      bin_filesize = lv_len
      filename     = lv_file
      filetype     = 'BIN'
    CHANGING
      data_tab     = lt_bin
    EXCEPTIONS
      OTHERS       = 1 ).

  IF sy-subrc = 0.
    WRITE: / lcl_t=>ui( d = `Datei geschrieben               :` e = `File written                     :` ), lv_file.
  ELSE.
    WRITE: / lcl_t=>ui( d = `Download fehlgeschlagen         :` e = `Download failed                  :` ), lv_file.
  ENDIF.

ENDFORM.

FORM download_srv USING iv_content TYPE string
                        iv_ext     TYPE string.

  DATA lv_x    TYPE xstring.
  DATA lv_file TYPE string.
  DATA lv_dir  TYPE string.
  DATA lv_base TYPE string.
  DATA lv_msg  TYPE string.

  lv_dir = p_srv.
  CONDENSE lv_dir.
  IF lv_dir IS INITIAL.
    RETURN.
  ENDIF.

  IF substring( val = lv_dir off = strlen( lv_dir ) - 1 len = 1 ) <> '/'.
    lv_dir = |{ lv_dir }/|.
  ENDIF.

  PERFORM file_base CHANGING lv_base.
  lv_file = |{ lv_dir }{ lv_base }.{ iv_ext }|.
  lv_x    = cl_abap_codepage=>convert_to( iv_content ).

  TRY.
      OPEN DATASET lv_file FOR OUTPUT IN BINARY MODE MESSAGE lv_msg.
      IF sy-subrc <> 0.
        WRITE: / lcl_t=>ui( d = `Serverdatei nicht anlegbar      :` e = `Server file cannot be created    :` ), lv_file, lv_msg.
        RETURN.
      ENDIF.
      TRANSFER lv_x TO lv_file.
      CLOSE DATASET lv_file.
      WRITE: / lcl_t=>ui( d = `Serverdatei geschrieben         :` e = `Server file written              :` ), lv_file.
    CATCH cx_root.
      WRITE: / lcl_t=>ui( d = `Serverdatei fehlgeschlagen      :` e = `Server file failed               :` ), lv_file.
  ENDTRY.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM import
*&---------------------------------------------------------------------*
* Reads the document from the PC or from the application server, parses
* it and hands it to the importer. Everything the run did is written to
* the list, including what it deliberately did not do.
*----------------------------------------------------------------------*
*&---------------------------------------------------------------------*
*& FORM ren_prepare
*&---------------------------------------------------------------------*
* Baut die Vorschlagsliste ALLER importierbaren Objekte. Zielname und
* Zielpaket sind mit dem Original bzw. dem Zielpaket vom Bild vorbelegt.
* Anlegen laesst sich nur im Kundennamensraum - das prueft ren_validate
* am Zielnamen. So kann auch ein SAP-/Fremdobjekt (z. B. FP_TEST_03) unter
* einem Z-Namen hereingeholt werden, ohne das Original zu ueberschreiben.
*----------------------------------------------------------------------*
FORM ren_prepare USING io_doc TYPE REF TO lcl_document.

  CLEAR gt_ren.
  DATA(lo_pl) = NEW lcl_importer( iv_test = abap_true
                                  iv_over = abap_false
                                  iv_act  = abap_false
                                  iv_pack = p_ipack
                                  iv_tr   = p_itr ).
  DATA(lt_work) = lo_pl->plan( io_doc ).

  LOOP AT lt_work INTO DATA(ls_w).
    APPEND VALUE ty_renrow(
      kind    = ls_w-kind
      oldname = ls_w-name
      newname = ls_w-name
      oldpack = ls_w-chapter->get_reference( )-tcode
      newpack = p_ipack ) TO gt_ren.
  ENDLOOP.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM ren_pbo  (PBO der Umbenennungs-Dynpro 2000)
*&---------------------------------------------------------------------*
* Baut einmalig den Docking-Container und das editierbare ALV-Grid auf
* und bindet es an gt_ren. Editierbar sind Zielname und Zielpaket.
*----------------------------------------------------------------------*
FORM ren_pbo.

  IF go_ren_grid IS BOUND.
    RETURN.
  ENDIF.

  CREATE OBJECT go_ren_dock
    EXPORTING repid     = sy-repid
              dynnr     = '2000'
              side      = cl_gui_docking_container=>dock_at_bottom
              extension = 2000.

  CREATE OBJECT go_ren_grid
    EXPORTING i_parent = go_ren_dock.

  DATA lt_fcat TYPE lvc_t_fcat.
  DATA ls_fcat TYPE lvc_s_fcat.
  CLEAR ls_fcat. ls_fcat-fieldname = 'KIND'.    ls_fcat-outputlen = 8.
  ls_fcat-coltext = lcl_t=>t( d = 'Objektart'    e = 'Object type' ).    APPEND ls_fcat TO lt_fcat.
  CLEAR ls_fcat. ls_fcat-fieldname = 'OLDNAME'. ls_fcat-outputlen = 30.
  ls_fcat-coltext = lcl_t=>t( d = 'Originalname' e = 'Original name' ).  APPEND ls_fcat TO lt_fcat.
  CLEAR ls_fcat. ls_fcat-fieldname = 'NEWNAME'. ls_fcat-outputlen = 30. ls_fcat-edit = 'X'.
  ls_fcat-coltext = lcl_t=>t( d = 'Zielname'     e = 'Target name' ).    APPEND ls_fcat TO lt_fcat.
  CLEAR ls_fcat. ls_fcat-fieldname = 'OLDPACK'. ls_fcat-outputlen = 20.
  ls_fcat-coltext = lcl_t=>t( d = 'Quellpaket'   e = 'Source package' ). APPEND ls_fcat TO lt_fcat.
  CLEAR ls_fcat. ls_fcat-fieldname = 'NEWPACK'. ls_fcat-outputlen = 20. ls_fcat-edit = 'X'.
  ls_fcat-coltext = lcl_t=>t( d = 'Zielpaket'    e = 'Target package' ). APPEND ls_fcat TO lt_fcat.

  DATA ls_lay TYPE lvc_s_layo.
  ls_lay-cwidth_opt = 'X'.
  ls_lay-grid_title = lcl_t=>t( d = 'Umzubenennende Objekte' e = 'Objects to rename' ).

  go_ren_grid->set_table_for_first_display(
    EXPORTING is_layout       = ls_lay
    CHANGING  it_outtab       = gt_ren
              it_fieldcatalog = lt_fcat ).

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM ren_pai  (PAI der Umbenennungs-Dynpro 2000)
*&---------------------------------------------------------------------*
* Uebernimmt die editierten Zellen in gt_ren und gibt Grid/Container
* beim Verlassen frei, damit ein weiterer Lauf sauber neu aufbaut.
*----------------------------------------------------------------------*
FORM ren_pai.

  IF go_ren_grid IS BOUND.
    go_ren_grid->check_changed_data( ).
  ENDIF.

  CASE sy-ucomm.
    WHEN 'ONLI' OR 'CANC' OR 'ENDE' OR 'ECAN' OR 'RW'.
      IF go_ren_grid IS BOUND.
        go_ren_grid->free( ).
        CLEAR go_ren_grid.
      ENDIF.
      IF go_ren_dock IS BOUND.
        go_ren_dock->free( ).
        CLEAR go_ren_dock.
      ENDIF.
  ENDCASE.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM ren_validate
*&---------------------------------------------------------------------*
* Prueft die Zielnamen: nicht leer, Kundennamensraum, keine Dubletten.
* Normalisiert auf Grossschreibung. Bei Fehler: Text in cv_err (Abbruch).
*----------------------------------------------------------------------*
FORM ren_validate CHANGING cv_err TYPE string.

  CLEAR cv_err.
  DATA lt_seen TYPE STANDARD TABLE OF string WITH EMPTY KEY.

  LOOP AT gt_ren ASSIGNING FIELD-SYMBOL(<ls>).
    DATA(lv_new) = <ls>-newname.
    CONDENSE lv_new.
    IF lv_new IS INITIAL.
      cv_err = |{ lcl_t=>ui( d = `Leerer Zielname fuer` e = `Empty target name for` ) } { <ls>-oldname }|.
      RETURN.
    ENDIF.
    TRANSLATE lv_new TO UPPER CASE.
    <ls>-newname = lv_new.
    DATA(lv_c) = lv_new(1).
    IF lv_c <> 'Z' AND lv_c <> 'Y' AND lv_c <> '/'.
      cv_err = |{ lcl_t=>ui( d = `Zielname nicht im Kundennamensraum:` e = `Target name not in customer namespace:` ) } { lv_new }|.
      RETURN.
    ENDIF.
    DATA(lv_key) = |{ <ls>-kind }/{ lv_new }|.
    READ TABLE lt_seen TRANSPORTING NO FIELDS WITH KEY table_line = lv_key.
    IF sy-subrc = 0.
      cv_err = |{ lcl_t=>ui( d = `Zielname doppelt:` e = `Duplicate target name:` ) } { lv_new }|.
      RETURN.
    ENDIF.
    APPEND lv_key TO lt_seen.
  ENDLOOP.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM ren_apply
*&---------------------------------------------------------------------*
* Wendet jede Umbenennung auf die ganze XML-Payload an: wort-genau und
* gross/klein-unabhaengig. Deckt sowohl Attributwerte (value="ALT") als
* auch Quelltext-Verwendungen (SELECT FROM alt, TYPE REF TO alt) ab. Nur
* Kundenobjekte werden umbenannt, deren Namen mit dem XML-Vokabular nicht
* kollidieren; die Wortgrenze verhindert Teiltreffer (ZKUNDE <> ZKUNDE2).
*----------------------------------------------------------------------*
FORM ren_apply CHANGING cv_xml TYPE string.

  LOOP AT gt_ren INTO DATA(ls).
    CHECK ls-newname <> ls-oldname.
    REPLACE ALL OCCURRENCES OF PCRE |\\b{ ls-oldname }\\b|
      IN cv_xml WITH ls-newname IGNORING CASE.
  ENDLOOP.

ENDFORM.

FORM import.

  DATA lv_xml  TYPE string.
  DATA lv_x    TYPE xstring.
  DATA lv_file TYPE string.
* GUI_UPLOAD and SCMS_BINARY_TO_XSTRING both expect the row structure
* SOLIX, not a plain X field. A table of elementary rows ends in
* CALL_FUNCTION_CONFLICT_TAB_TYP.
  DATA lt_bin  TYPE solix_tab.
  DATA lv_len  TYPE i.

  lv_file = p_ifile.
  CONDENSE lv_file.
  IF lv_file IS INITIAL.
    WRITE: / lcl_t=>ui( d = `Keine Datei angegeben.` e = `No file given.` ).
    RETURN.
  ENDIF.

  IF p_isrv = abap_true.
    OPEN DATASET lv_file FOR INPUT IN BINARY MODE.
    IF sy-subrc <> 0.
      WRITE: / lcl_t=>ui( d = `Serverdatei nicht lesbar        :`
                          e = `Server file cannot be read       :` ), lv_file.
      RETURN.
    ENDIF.
    READ DATASET lv_file INTO lv_x MAXIMUM LENGTH 20000000.
    CLOSE DATASET lv_file.
  ELSE.
    IF sy-batch = abap_true.
      WRITE: / lcl_t=>ui( d = `Im Hintergrund gibt es keinen PC-Zugriff. Datei auf dem Applikationsserver ablegen.`
                          e = `There is no PC access in the background. Put the file on the application server.` ).
      RETURN.
    ENDIF.
    CALL FUNCTION 'GUI_UPLOAD'
      EXPORTING  filename   = lv_file
                 filetype   = 'BIN'
      IMPORTING  filelength = lv_len
      TABLES     data_tab   = lt_bin
      EXCEPTIONS OTHERS     = 1.
    IF sy-subrc <> 0.
      WRITE: / lcl_t=>ui( d = `Datei nicht lesbar              :`
                          e = `File cannot be read              :` ), lv_file.
      RETURN.
    ENDIF.
    CALL FUNCTION 'SCMS_BINARY_TO_XSTRING'
      EXPORTING  input_length = lv_len
      IMPORTING  buffer       = lv_x
      TABLES     binary_tab   = lt_bin
      EXCEPTIONS OTHERS       = 1.
    IF sy-subrc <> 0.
      WRITE: / lcl_t=>ui( d = `Datei nicht wandelbar.` e = `File cannot be converted.` ).
      RETURN.
    ENDIF.
  ENDIF.

  IF lv_x IS INITIAL.
    WRITE: / lcl_t=>ui( d = `Datei ist leer.` e = `File is empty.` ).
    RETURN.
  ENDIF.

  TRY.
      lv_xml = cl_abap_codepage=>convert_from( lv_x ).
    CATCH cx_root.
      WRITE: / lcl_t=>ui( d = `Datei ist kein UTF-8.` e = `File is not UTF-8.` ).
      RETURN.
  ENDTRY.

  DATA lo_doc TYPE REF TO lcl_document.
  TRY.
      lo_doc = lcl_parser_xml=>parse( lv_xml ).
    CATCH cx_root.
      WRITE: / lcl_t=>ui( d = `Datei ist kein Documizer-XML.`
                          e = `File is not a Documizer XML.` ).
      RETURN.
  ENDTRY.

* Optionale Objekt-Umbenennung vor dem Import. Nur im Dialog moeglich -
* die editierbare Liste braucht die GUI. Bei ungueltiger Eingabe: Abbruch.
  IF p_iren = abap_true.
    IF sy-batch = abap_true.
      WRITE: / lcl_t=>ui( d = `Umbenennen geht nur im Dialog - im Hintergrund uebersprungen.`
                          e = `Rename works only in dialog - skipped in background.` ).
    ELSE.
      PERFORM ren_prepare USING lo_doc.
      IF gt_ren IS NOT INITIAL.
        CALL SELECTION-SCREEN 2000 STARTING AT 5 3.
        IF sy-subrc <> 0.
          WRITE: / lcl_t=>ui( d = `Import abgebrochen.` e = `Import cancelled.` ).
          RETURN.
        ENDIF.
        DATA lv_rerr TYPE string.
        PERFORM ren_validate CHANGING lv_rerr.
        IF lv_rerr IS NOT INITIAL.
          WRITE: / lcl_t=>ui( d = `Umbenennung ungueltig:` e = `Rename invalid:` ), lv_rerr.
          RETURN.
        ENDIF.
        PERFORM ren_apply CHANGING lv_xml.
        TRY.
            lo_doc = lcl_parser_xml=>parse( lv_xml ).
          CATCH cx_root.
            WRITE: / lcl_t=>ui( d = `Umbenanntes XML nicht mehr lesbar.`
                                e = `Renamed XML no longer parseable.` ).
            RETURN.
        ENDTRY.
      ENDIF.
    ENDIF.
  ENDIF.

  DATA(ls_meta) = lo_doc->get_meta( ).
  WRITE: / lcl_t=>ui( d = `Import` e = `Import` ).
  ULINE.
  WRITE: / lcl_t=>ui( d = `Datei                            :` e = `File                             :` ), lv_file.
  WRITE: / lcl_t=>ui( d = `Quellsystem                      :` e = `Source system                    :` ),
           ls_meta-system, '/', ls_meta-client.
  WRITE: / lcl_t=>ui( d = `Erzeugt                          :` e = `Created                          :` ),
           ls_meta-created_at, ls_meta-created_by.
  WRITE: / lcl_t=>ui( d = `Zielpaket                        :` e = `Target package                   :` ), p_ipack.
  IF p_itr IS NOT INITIAL.
    WRITE: / lcl_t=>ui( d = `Auftrag                          :` e = `Request                          :` ), p_itr.
  ENDIF.
  IF p_itest = abap_true.
    WRITE: / lcl_t=>ui( d = `TESTLAUF - es wird nichts angelegt.`
                        e = `TEST RUN - nothing is created.` ).
  ENDIF.

* Die vier Regelzeilen vom Bild werden hier zur Tabelle. Leere Zeilen
* fallen weg; eine Regel ohne Ziel waere keine.
  DATA lt_pmap TYPE ty_packmaps.
  IF p_iold1 IS NOT INITIAL AND p_inew1 IS NOT INITIAL.
    APPEND VALUE ty_packmap( from = p_iold1 to = p_inew1 ) TO lt_pmap.
  ENDIF.
  IF p_iold2 IS NOT INITIAL AND p_inew2 IS NOT INITIAL.
    APPEND VALUE ty_packmap( from = p_iold2 to = p_inew2 ) TO lt_pmap.
  ENDIF.
  IF p_iold3 IS NOT INITIAL AND p_inew3 IS NOT INITIAL.
    APPEND VALUE ty_packmap( from = p_iold3 to = p_inew3 ) TO lt_pmap.
  ENDIF.
  IF p_iold4 IS NOT INITIAL AND p_inew4 IS NOT INITIAL.
    APPEND VALUE ty_packmap( from = p_iold4 to = p_inew4 ) TO lt_pmap.
  ENDIF.

  IF lt_pmap IS NOT INITIAL.
    LOOP AT lt_pmap INTO DATA(ls_pmap).
      WRITE: / lcl_t=>ui( d = `Paketregel                       :`
                          e = `Package rule                     :` ),
               ls_pmap-from, '->', ls_pmap-to.
    ENDLOOP.
  ENDIF.
  IF p_ikeep = abap_true.
    WRITE: / lcl_t=>ui( d = `Quellpaket beibehalten, wo keine Regel greift.`
                        e = `Source package kept where no rule applies.` ).
  ENDIF.

  IF p_itest = abap_false.
    PERFORM ensure_task.
  ENDIF.

  SKIP.

  DATA(lo_imp) = NEW lcl_importer( iv_test = p_itest
                                   iv_over = p_iover
                                   iv_act  = p_iact
                                   iv_pack = p_ipack
                                   iv_tr   = p_itr
                                   iv_keep = p_ikeep
                                   it_map  = lt_pmap ).
  IF p_iren = abap_true.
    lo_imp->set_renames( gt_ren ).
  ENDIF.
  lo_imp->run( lo_doc ).

* Fixed-width columns through typed fields, not through offsets on the
* string itself - a name shorter than the column would end the run in
* STRING_LENGTH_TOO_LARGE.
  DATA lv_n    TYPE i.
  DATA lv_ckind TYPE c LENGTH 6.
  DATA lv_cname TYPE c LENGTH 40.
  DATA lv_cact  TYPE c LENGTH 24.
  LOOP AT lo_imp->get_log( ) INTO DATA(ls_log).
    lv_n = lv_n + 1.
    lv_ckind = ls_log-kind.
    lv_cname = ls_log-name.
    lv_cact  = ls_log-action.
    WRITE: / lv_ckind, lv_cname, lv_cact, ls_log-text.
  ENDLOOP.
  IF lv_n = 0.
    WRITE: / lcl_t=>ui( d = `Nichts verarbeitet.` e = `Nothing processed.` ).
  ELSE.
    SKIP.
    WRITE: / lcl_t=>ui( d = `Zeilen im Protokoll              :`
                        e = `Lines in the protocol            :` ), lv_n.
  ENDIF.

ENDFORM.

*----------------------------------------------------------------------*
* Main flow
*----------------------------------------------------------------------*
*----------------------------------------------------------------------*
* lcl_request
*----------------------------------------------------------------------*
* Der Leser der Fehlliste. Sie kommt aus dem IMG-Report des
* Zielsystems und traegt nur Typ und Name je Objekt - mehr braucht es
* nicht, um hier eine Arbeitsliste daraus zu machen.
*
* Bewusst ein eigenes, winziges Format: das DEV-Dokument und das
* IMG-Dokument sprechen verschiedene Vokabulare, und eines davon zu
* verbiegen kostet mehr als dreissig Zeilen hier.
CLASS lcl_request DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS parse
      IMPORTING iv_xml         TYPE string
      EXPORTING ev_source      TYPE string
      RETURNING VALUE(rt_objs) TYPE ty_objrefs.
ENDCLASS.

CLASS lcl_request IMPLEMENTATION.

  METHOD parse.

    DATA lo_reader TYPE REF TO if_sxml_reader.
    DATA lv_target TYPE string.

    CLEAR ev_source.
    lo_reader = cl_sxml_string_reader=>create( cl_abap_codepage=>convert_to( iv_xml ) ).

    DO.

      DATA(lo_node) = lo_reader->read_next_node( ).
      IF lo_node IS INITIAL.
        EXIT.
      ENDIF.

      CASE lo_node->type.

        WHEN if_sxml_node=>co_nt_element_open.

          DATA(lo_open) = CAST if_sxml_open_element( lo_node ).
          CLEAR lv_target.

          CASE lo_open->qname-name.

            WHEN 'object'.
              DATA ls_obj TYPE ty_objref.
              CLEAR ls_obj.
              LOOP AT lo_open->get_attributes( ) INTO DATA(lo_attr).
                CASE lo_attr->qname-name.
                  WHEN 'type'. ls_obj-type = to_upper( lo_attr->get_value( ) ).
                  WHEN 'name'. ls_obj-name = to_upper( lo_attr->get_value( ) ).
                ENDCASE.
              ENDLOOP.
*             Ein Auftrag ohne Typ oder Name ist keiner. Lieber
*             stillschweigend uebergehen als ein leeres Objekt
*             dokumentieren wollen.
              IF ls_obj-type IS NOT INITIAL AND ls_obj-name IS NOT INITIAL.
                READ TABLE rt_objs TRANSPORTING NO FIELDS
                     WITH KEY type = ls_obj-type name = ls_obj-name.
                IF sy-subrc <> 0.
                  APPEND ls_obj TO rt_objs.
                ENDIF.
              ENDIF.

            WHEN 'source'.
              lv_target = 'source'.

          ENDCASE.

        WHEN if_sxml_node=>co_nt_value.

          IF lv_target = 'source'.
            ev_source = CAST if_sxml_value_node( lo_node )->get_value( ).
          ENDIF.

        WHEN if_sxml_node=>co_nt_element_close.
          CLEAR lv_target.

      ENDCASE.

    ENDDO.

  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* Fehlliste einlesen
*----------------------------------------------------------------------*
FORM read_request CHANGING ct_objs   TYPE ty_objrefs
                           cv_source TYPE string.

  DATA lv_file TYPE string.
  DATA lv_x    TYPE xstring.
  DATA lt_bin  TYPE solix_tab.
  DATA lv_len  TYPE i.
  DATA lv_xml  TYPE string.

  CLEAR: ct_objs, cv_source.

  lv_file = p_afile.
  CONDENSE lv_file.

  IF p_asrv = abap_true.
    OPEN DATASET lv_file FOR INPUT IN BINARY MODE.
    IF sy-subrc <> 0.
      WRITE: / lcl_t=>ui( d = `Serverdatei nicht lesbar        :`
                          e = `Server file cannot be read       :` ), lv_file.
      RETURN.
    ENDIF.
    READ DATASET lv_file INTO lv_x MAXIMUM LENGTH 20000000.
    CLOSE DATASET lv_file.
  ELSE.
    IF sy-batch = abap_true.
      WRITE: / lcl_t=>ui( d = `Im Hintergrund gibt es keinen PC-Zugriff.`
                          e = `There is no PC access in the background.` ).
      RETURN.
    ENDIF.
    CALL FUNCTION 'GUI_UPLOAD'
      EXPORTING  filename   = lv_file
                 filetype   = 'BIN'
      IMPORTING  filelength = lv_len
      TABLES     data_tab   = lt_bin
      EXCEPTIONS OTHERS     = 1.
    IF sy-subrc <> 0.
      WRITE: / lcl_t=>ui( d = `Datei nicht lesbar              :`
                          e = `File cannot be read              :` ), lv_file.
      RETURN.
    ENDIF.
    CALL FUNCTION 'SCMS_BINARY_TO_XSTRING'
      EXPORTING  input_length = lv_len
      IMPORTING  buffer       = lv_x
      TABLES     binary_tab   = lt_bin
      EXCEPTIONS OTHERS       = 1.
    IF sy-subrc <> 0.
      WRITE: / lcl_t=>ui( d = `Datei nicht wandelbar.` e = `File cannot be converted.` ).
      RETURN.
    ENDIF.
  ENDIF.

  IF lv_x IS INITIAL.
    WRITE: / lcl_t=>ui( d = `Datei ist leer.` e = `File is empty.` ).
    RETURN.
  ENDIF.

  TRY.
      lv_xml = cl_abap_codepage=>convert_from( lv_x ).
    CATCH cx_root.
      WRITE: / lcl_t=>ui( d = `Datei ist kein UTF-8.` e = `File is not UTF-8.` ).
      RETURN.
  ENDTRY.

  TRY.
      ct_objs = lcl_request=>parse( EXPORTING iv_xml    = lv_xml
                                    IMPORTING ev_source = cv_source ).
    CATCH cx_root.
      WRITE: / lcl_t=>ui( d = `Datei ist keine Documizer-Fehlliste.`
                          e = `File is not a Documizer request list.` ).
  ENDTRY.

ENDFORM.

START-OF-SELECTION.

* The document speaks the output language, including its own headings.
  lcl_t=>set_lang( p_langu ).

* Import is the other direction and shares nothing with the run below
* but the model in between: read the file, parse it, create the objects.
  IF p_imp = abap_true.
    PERFORM import.
    RETURN.
  ENDIF.

* Beim Startpunkt-Typ AL kommen die Objekte aus der Fehlliste. Ohne
* lesbare Datei gibt es nichts zu tun - lieber hier aufhoeren als ein
* leeres Dokument erzeugen.
  DATA lt_start TYPE ty_objrefs.
  DATA lv_rsrc  TYPE string.
  IF p_stype = 'AL'.
    WRITE: / lcl_t=>ui( d = `Documizer - Entwicklerdokumentation` e = `Documizer - developer documentation` ).
    ULINE.
    PERFORM read_request CHANGING lt_start lv_rsrc.
    IF lt_start IS INITIAL.
      WRITE: / lcl_t=>ui( d = `Keine Objekte in der Fehlliste.`
                          e = `No objects in the request list.` ).
      RETURN.
    ENDIF.
    WRITE: / lcl_t=>ui( d = `Fehlliste                        :` e = `Request list                     :` ), p_afile.
    IF lv_rsrc IS NOT INITIAL.
      WRITE: / lcl_t=>ui( d = `angefordert von                  :` e = `requested by                     :` ), lv_rsrc.
    ENDIF.
    WRITE: / lcl_t=>ui( d = `Angeforderte Objekte             :` e = `Objects requested                :` ), lines( lt_start ).
    SKIP.
  ENDIF.

  DATA(lo_collector) = NEW lcl_collector_dev( iv_stype  = p_stype
                                              iv_sval   = CONV string( p_sval )
                                              iv_rdep   = p_rdep
                                              iv_recur  = p_recur
                                              iv_local  = p_local
                                              iv_langu  = p_langu
                                              iv_maxobj = p_maxobj
                                              iv_doku   = p_doku
                                              iv_detail = p_detail
                                              iv_src    = p_src
                                              iv_maxsrc = p_maxsrc
                                              iv_used   = p_used
                                              iv_useall = p_useall
                                              iv_maxuse = p_maxuse
                                              iv_falb   = p_falb
                                              iv_flang  = p_flang
                                              iv_calls  = p_calls
                                              iv_nosap  = p_nosap
                                              iv_maxhit = p_maxhit
                                              iv_fsrc   = p_fsrc
                                              iv_udep   = p_udep
                                              iv_def    = p_def
                                              it_start  = lt_start ).

  DATA lo_coll TYPE REF TO lif_docu_collector.
  lo_coll = lo_collector.

  DATA(lo_doc) = lo_coll->collect( ).

  DATA lo_renderer TYPE REF TO lif_docu_renderer.
  lo_renderer = NEW lcl_renderer_xml( ).

  DATA lv_xml TYPE string.
  IF p_xml = abap_true OR p_rtest = abap_true.
    lv_xml = lo_renderer->render( lo_doc ).
  ENDIF.

  DATA(ls_docmeta) = lo_doc->get_meta( ).

  IF p_stype <> 'AL'.
    WRITE: / lcl_t=>ui( d = `Documizer - Entwicklerdokumentation` e = `Documizer - developer documentation` ).
    ULINE.
  ENDIF.
  PERFORM stype_text USING p_stype CHANGING gv_tstyt.
  WRITE: / lcl_t=>ui( d = `Startpunkt                       :` e = `Start point                      :` ), gv_tstyt(20), p_sval.
  IF p_stype = 'K'.
    WRITE: / lcl_t=>ui( d = `Pakete                           :` e = `Packages                         :` ), lo_collector->get_stat_packages( ).
  ENDIF.
  WRITE: / lcl_t=>ui( d = `Objekte aufgenommen              :` e = `Objects included                 :` ), lo_collector->get_stat_objects( ).
  WRITE: / lcl_t=>ui( d = `Objekte gefunden                 :` e = `Objects found                    :` ), lo_collector->get_stat_total( ).
  WRITE: / lcl_t=>ui( d = `mit Objektdokumentation          :` e = `with object documentation        :` ), lo_collector->get_stat_docu( ).
  IF p_src = abap_true.
    WRITE: / lcl_t=>ui( d = `mit Quelltext                    :` e = `with source code                 :` ), lo_collector->get_stat_source( ).
  ENDIF.
  IF p_used = abap_true.
    WRITE: / lcl_t=>ui( d = `mit Verwendungsnachweis          :` e = `with where-used list             :` ), lo_collector->get_stat_usage( ).
  ENDIF.
  IF p_calls = abap_true.
    WRITE: / lcl_t=>ui( d = `mit ausgehenden Aufrufen         :` e = `with outgoing references         :` ), lo_collector->get_stat_calls( ).
  ENDIF.
  IF p_falb = abap_true.
    WRITE: / lcl_t=>ui( d = `davon in Ersatzsprache           :` e = `of these in the fallback language:` ), lo_collector->get_stat_fallback( ).
  ENDIF.
  IF lv_xml IS NOT INITIAL.
    WRITE: / lcl_t=>ui( d = `XML-Zeichen                      :` e = `XML characters                   :` ), strlen( lv_xml ).
  ENDIF.

  IF ls_docmeta-node_limit > 0 AND ls_docmeta-node_total > ls_docmeta-node_limit.
    WRITE: / lcl_t=>ui( d = `ACHTUNG: Objektgrenze erreicht, Dokument unvollständig.` e = `CAUTION: object limit reached, document is incomplete.` ).
  ENDIF.
  IF ls_docmeta-src_trunc = abap_true.
    WRITE: / lcl_t=>ui( d = `ACHTUNG: Quelltext an der Zeilengrenze abgeschnitten.` e = `CAUTION: source truncated at the line limit.` ).
  ENDIF.

  IF p_rtest = abap_true AND lv_xml IS NOT INITIAL.
    DATA(lo_doc2) = lcl_parser_xml=>parse( lv_xml ).
    DATA(lv_xml2) = lo_renderer->render( lo_doc2 ).
    IF lv_xml = lv_xml2.
      WRITE: / lcl_t=>ui( d = `Roundtrip                        : IDENTISCH - bestanden` e = `Roundtrip                        : IDENTICAL - passed` ).
    ELSE.
      WRITE: / lcl_t=>ui( d = `Roundtrip                        : ABWEICHUNG` e = `Roundtrip                        : DEVIATION` ), strlen( lv_xml2 ).
    ENDIF.
  ENDIF.

  IF p_xml = abap_true.
    IF p_down = abap_true.
      PERFORM download USING lv_xml 'xml'.
    ENDIF.
    IF p_dsrv = abap_true AND p_srv IS NOT INITIAL.
      PERFORM download_srv USING lv_xml 'xml'.
    ENDIF.
  ENDIF.

  IF p_html = abap_true.
    DATA lo_html TYPE REF TO lif_docu_renderer.
    lcl_renderer_html=>set_fold( p_fold ).
    lo_html = NEW lcl_renderer_html( ).
    DATA(lv_html) = lo_html->render( lo_doc ).
    WRITE: / lcl_t=>ui( d = `HTML-Zeichen                     :` e = `HTML characters                  :` ), strlen( lv_html ).
    IF p_down = abap_true.
      PERFORM download USING lv_html 'html'.
    ENDIF.
    IF p_dsrv = abap_true AND p_srv IS NOT INITIAL.
      PERFORM download_srv USING lv_html 'html'.
    ENDIF.
    IF sy-batch = abap_false.
      cl_abap_browser=>show_html( html_string = lv_html
                                  title       = 'Documizer' ).
    ENDIF.
  ENDIF.

  IF p_xml = abap_true.
    SKIP.
    WRITE: / lcl_t=>ui( d = `Erzeugtes XML` e = `Generated XML` ).
    ULINE.
    DATA(lv_pretty) = lo_renderer->render( io_document = lo_doc iv_pretty = abap_true ).
    SPLIT lv_pretty AT cl_abap_char_utilities=>newline INTO TABLE DATA(lt_lines).
    LOOP AT lt_lines INTO DATA(lv_line).
      WRITE: / lv_line.
    ENDLOOP.
  ENDIF.
