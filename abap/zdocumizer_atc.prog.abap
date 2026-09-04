REPORT zdocumizer_atc.

************************************************************************
* consiness Documizer - ATC-/Code-Inspector-Pruefkonfiguration
*
* Dokumentiert, welche Regeln ein System erzwingt: die Pruefvarianten,
* die darin enthaltenen Checks, deren Meldungen mit Prioritaet und die
* Pseudokommentare bzw. Pragmas, mit denen sich eine Meldung
* unterdruecken laesst.
*
* Das ist die dritte Sicht neben Customizing und Entwicklung: nicht was
* im System steht, sondern woran es gemessen wird.
*
* Alles liegt in einem Report, damit er nach Copy/Paste in SE38 auf
* jedem System laeuft - Kapitelmodell, XML-Renderer und Parser sind
* wortgleich mit ZDOCUMIZER_IMG und ZDOCUMIZER_DEV.
*
* Verwendete Schnittstellen:
*   CL_CI_CHECKVARIANT=>GET_REF / GET_INFO   Pruefvariante mit Checkliste
*   CL_CI_TESTS=>GET_TEST_REF                Instanz einer Checkklasse
*   CL_CI_TESTS=>GET_TESTS                   alle aktivierten Checks
*   CL_CI_TESTS=>GET_MESSAGE_TEXT            Meldungstext
*   SCIPRIORITIES                            kundeneigene Priorisierung
*
* Die Checkliste einer Variante steht nicht als lesbare Tabelle in der
* Datenbank: SCICHKV_PA ist ein INDX-Cluster. Deshalb fuehrt der Weg
* ueber die API und nicht ueber SELECT.
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

TYPES: BEGIN OF ty_project,
         project TYPE string,
         status  TYPE string,
         done    TYPE string,
         memo    TYPE string,
       END OF ty_project.

TYPES: BEGIN OF ty_transport,
         trkorr TYPE string,
         user   TYPE string,
         date   TYPE string,
         text   TYPE string,
       END OF ty_transport.
TYPES ty_transports TYPE STANDARD TABLE OF ty_transport WITH EMPTY KEY.

TYPES: BEGIN OF ty_reference,
         activity TYPE string,
         docu_id  TYPE string,
         tcode    TYPE string,
       END OF ty_reference.

TYPES ty_names TYPE STANDARD TABLE OF sobj_name WITH EMPTY KEY.

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
       END OF ty_meta.

TYPES ty_chapters TYPE STANDARD TABLE OF REF TO lcl_chapter WITH EMPTY KEY.
TYPES ty_objects  TYPE STANDARD TABLE OF REF TO lcl_object  WITH EMPTY KEY.

CONSTANTS gc_version  TYPE string VALUE '1.0'.
CONSTANTS gc_docuclas TYPE dokhl-id VALUE 'HY'.
CONSTANTS gc_reftype  TYPE string VALUE 'COBJ'.

*----------------------------------------------------------------------*
* lcl_object
*----------------------------------------------------------------------*
CLASS lcl_object DEFINITION.
  PUBLIC SECTION.
    METHODS constructor
      IMPORTING iv_type TYPE string
                iv_name TYPE string
                iv_tcode TYPE string OPTIONAL.
    METHODS add_field     IMPORTING is_field     TYPE ty_field.
    METHODS add_row       IMPORTING is_row       TYPE ty_row.
    METHODS set_row_count IMPORTING iv_row_count TYPE i.
    METHODS set_truncated IMPORTING iv_truncated TYPE abap_bool.
    METHODS get_type      RETURNING VALUE(rv_type)      TYPE string.
    METHODS get_name      RETURNING VALUE(rv_name)      TYPE string.
    METHODS get_tcode     RETURNING VALUE(rv_tcode)     TYPE string.
    METHODS get_fields    RETURNING VALUE(rt_fields)    TYPE ty_fields.
    METHODS get_rows      RETURNING VALUE(rt_rows)      TYPE ty_rows.
    METHODS get_row_count RETURNING VALUE(rv_row_count) TYPE i.
    METHODS get_truncated RETURNING VALUE(rv_truncated) TYPE abap_bool.
    METHODS set_object    IMPORTING iv_objtype TYPE string
                                    iv_objname TYPE string.
    METHODS get_objtype   RETURNING VALUE(rv_type) TYPE string.
    METHODS get_objname   RETURNING VALUE(rv_name) TYPE string.
    METHODS set_note      IMPORTING iv_note   TYPE string.
    METHODS get_note      RETURNING VALUE(rv_note)   TYPE string.
    METHODS set_filter    IMPORTING iv_filter TYPE string.
    METHODS get_filter    RETURNING VALUE(rv_filter) TYPE string.
    METHODS add_transport IMPORTING is_transport TYPE ty_transport.
    METHODS get_transports RETURNING VALUE(rt_transports) TYPE ty_transports.
  PRIVATE SECTION.
    DATA mv_type      TYPE string.
    DATA mv_name      TYPE string.
    DATA mv_tcode     TYPE string.
    DATA mt_fields    TYPE ty_fields.
    DATA mt_rows      TYPE ty_rows.
    DATA mv_row_count TYPE i.
    DATA mv_truncated TYPE abap_bool.
    DATA mv_note      TYPE string.
    DATA mv_filter    TYPE string.
*   Das Pflegeobjekt der IMG-Aktivitaet - Sicht, Sichtcluster oder
*   Tabelle. mv_name traegt die aufgeloeste Basistabelle; wer den
*   Pflegeapparat nachziehen will, braucht aber das Objekt selbst.
*   Frueher stand es nur im Prosa-Hinweis, und der wechselt die
*   Sprache.
    DATA mv_objtype   TYPE string.
    DATA mv_objname   TYPE string.
    DATA mt_trans     TYPE ty_transports.
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
  METHOD get_type.
    rv_type = mv_type.
  ENDMETHOD.
  METHOD get_name.
    rv_name = mv_name.
  ENDMETHOD.
  METHOD get_tcode.
    rv_tcode = mv_tcode.
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
  METHOD set_object.
    mv_objtype = iv_objtype.
    mv_objname = iv_objname.
  ENDMETHOD.
  METHOD get_objtype.
    rv_type = mv_objtype.
  ENDMETHOD.
  METHOD get_objname.
    rv_name = mv_objname.
  ENDMETHOD.
  METHOD set_note.
    mv_note = iv_note.
  ENDMETHOD.
  METHOD get_note.
    rv_note = mv_note.
  ENDMETHOD.
  METHOD set_filter.
    mv_filter = iv_filter.
  ENDMETHOD.
  METHOD get_filter.
    rv_filter = mv_filter.
  ENDMETHOD.
  METHOD add_transport.
    APPEND is_transport TO mt_trans.
  ENDMETHOD.
  METHOD get_transports.
    rt_transports = mt_trans.
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
    METHODS set_doclang       IMPORTING iv_lang      TYPE string.
    METHODS get_doclang       RETURNING VALUE(rv_lang) TYPE string.
    METHODS set_title         IMPORTING iv_title     TYPE string.
    METHODS set_type          IMPORTING iv_type      TYPE string.
    METHODS get_id            RETURNING VALUE(rv_id)        TYPE string.
    METHODS get_level         RETURNING VALUE(rv_level)     TYPE i.
    METHODS get_type          RETURNING VALUE(rv_type)      TYPE string.
    METHODS get_title         RETURNING VALUE(rv_title)     TYPE string.
    METHODS get_children      RETURNING VALUE(rt_children)  TYPE ty_chapters.
    METHODS get_objects       RETURNING VALUE(rt_objects)   TYPE ty_objects.
    METHODS get_reference     RETURNING VALUE(rs_reference) TYPE ty_reference.
    METHODS get_documentation RETURNING VALUE(rv_text)      TYPE string.
    METHODS has_reference     RETURNING VALUE(rv_flag)      TYPE abap_bool.
    METHODS set_project       IMPORTING is_project TYPE ty_project.
    METHODS get_project       RETURNING VALUE(rs_project) TYPE ty_project.
    METHODS has_project       RETURNING VALUE(rv_flag)    TYPE abap_bool.
    METHODS set_children      IMPORTING it_children TYPE ty_chapters.
  PRIVATE SECTION.
    DATA ms_project       TYPE ty_project.
    DATA mv_id            TYPE string.
    DATA mv_level         TYPE i.
    DATA mv_type          TYPE string.
    DATA mv_title         TYPE string.
    DATA ms_reference     TYPE ty_reference.
    DATA mv_documentation TYPE string.
    DATA mv_doclang       TYPE string.
    DATA mt_children      TYPE ty_chapters.
    DATA mt_objects       TYPE ty_objects.
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
  METHOD set_doclang.
    mv_doclang = iv_lang.
  ENDMETHOD.
  METHOD get_doclang.
    rv_lang = mv_doclang.
  ENDMETHOD.
  METHOD set_title.
    mv_title = iv_title.
  ENDMETHOD.
  METHOD set_type.
    mv_type = iv_type.
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
  METHOD set_project.
    ms_project = is_project.
  ENDMETHOD.
  METHOD get_project.
    rs_project = ms_project.
  ENDMETHOD.
  METHOD has_project.
    IF ms_project IS INITIAL.
      rv_flag = abap_false.
    ELSE.
      rv_flag = abap_true.
    ENDIF.
  ENDMETHOD.
  METHOD set_children.
    mt_children = it_children.
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
    METHODS set_chapters IMPORTING it_chapters TYPE ty_chapters.
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
  METHOD set_chapters.
    mt_chapters = it_chapters.
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
      mo_writer->write_attribute( name = 'activity' value = ls_ref-activity ).
      mo_writer->write_attribute( name = 'docu_id'  value = ls_ref-docu_id ).
      mo_writer->write_attribute( name = 'tcode'    value = ls_ref-tcode ).
      mo_writer->close_element( ).
    ENDIF.

    IF io_chapter->get_documentation( ) IS NOT INITIAL.
      mo_writer->open_element( name = 'documentation' ).
      mo_writer->write_attribute( name = 'format' value = 'ITF' ).
      mo_writer->write_attribute( name = 'lang'   value = io_chapter->get_doclang( ) ).
      mo_writer->write_value( io_chapter->get_documentation( ) ).
      mo_writer->close_element( ).
    ENDIF.

    IF io_chapter->has_project( ) = abap_true.
      DATA(ls_pr) = io_chapter->get_project( ).
      mo_writer->open_element( name = 'project' ).
      mo_writer->write_attribute( name = 'name'   value = ls_pr-project ).
      mo_writer->write_attribute( name = 'status' value = ls_pr-status ).
      mo_writer->write_attribute( name = 'done'   value = ls_pr-done ).
      IF ls_pr-memo IS NOT INITIAL.
        mo_writer->write_value( ls_pr-memo ).
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
    mo_writer->write_attribute( name = 'type'  value = io_object->get_type( ) ).
    mo_writer->write_attribute( name = 'name'  value = io_object->get_name( ) ).
    mo_writer->write_attribute( name = 'tcode'  value = io_object->get_tcode( ) ).
    mo_writer->write_attribute( name = 'filter' value = io_object->get_filter( ) ).
    mo_writer->write_attribute( name = 'note'   value = io_object->get_note( ) ).
    mo_writer->write_attribute( name = 'objtype' value = io_object->get_objtype( ) ).
    mo_writer->write_attribute( name = 'objname' value = io_object->get_objname( ) ).

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

    mo_writer->open_element( name = 'data' ).
    mo_writer->write_attribute( name = 'row_count' value = |{ io_object->get_row_count( ) }| ).
    IF io_object->get_truncated( ) = abap_true.
      mo_writer->write_attribute( name = 'truncated' value = 'true' ).
    ELSE.
      mo_writer->write_attribute( name = 'truncated' value = 'false' ).
    ENDIF.
    LOOP AT io_object->get_rows( ) INTO DATA(ls_row).
      mo_writer->open_element( name = 'row' ).
      LOOP AT ls_row-cells INTO DATA(ls_cell).
        mo_writer->open_element( name = 'f' ).
        mo_writer->write_attribute( name = 'n' value = ls_cell-name ).
        IF ls_cell-value IS NOT INITIAL.
          mo_writer->write_value( ls_cell-value ).
        ENDIF.
        mo_writer->close_element( ).
      ENDLOOP.
      mo_writer->close_element( ).
    ENDLOOP.
    mo_writer->close_element( ).

    mo_writer->open_element( name = 'transports' ).
    LOOP AT io_object->get_transports( ) INTO DATA(ls_tr).
      mo_writer->open_element( name = 'transport' ).
      mo_writer->write_attribute( name = 'trkorr' value = ls_tr-trkorr ).
      mo_writer->write_attribute( name = 'user'   value = ls_tr-user ).
      mo_writer->write_attribute( name = 'date'   value = ls_tr-date ).
      mo_writer->write_attribute( name = 'text'   value = ls_tr-text ).
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
    DATA ls_row     TYPE ty_row.
    DATA ls_cell    TYPE ty_cell.
    DATA lv_target  TYPE string.

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
              OR 'language' OR 'truncated' OR 'node_limit' OR 'node_total'.
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

            WHEN 'project'.
              DATA ls_pr TYPE ty_project.
              CLEAR ls_pr.
              LOOP AT lt_attr INTO lo_attr.
                CASE lo_attr->qname-name.
                  WHEN 'name'.   ls_pr-project = lo_attr->get_value( ).
                  WHEN 'status'. ls_pr-status  = lo_attr->get_value( ).
                  WHEN 'done'.   ls_pr-done    = lo_attr->get_value( ).
                ENDCASE.
              ENDLOOP.
              IF lo_current IS BOUND.
                lo_current->set_project( ls_pr ).
              ENDIF.
              lv_target = 'projectmemo'.

            WHEN 'reference'.
              DATA ls_ref TYPE ty_reference.
              CLEAR ls_ref.
              LOOP AT lt_attr INTO lo_attr.
                CASE lo_attr->qname-name.
                  WHEN 'activity'. ls_ref-activity = lo_attr->get_value( ).
                  WHEN 'docu_id'.  ls_ref-docu_id  = lo_attr->get_value( ).
                  WHEN 'tcode'.    ls_ref-tcode    = lo_attr->get_value( ).
                ENDCASE.
              ENDLOOP.
              IF lo_current IS BOUND.
                lo_current->set_reference( ls_ref ).
              ENDIF.

            WHEN 'object'.
              DATA lv_otype TYPE string.
              DATA lv_oname TYPE string.
              DATA lv_otcod TYPE string.
              DATA lv_ofilt TYPE string.
              DATA lv_onote TYPE string.
              DATA lv_optyp TYPE string.
              DATA lv_opnam TYPE string.
*             Alle Attribute zuruecksetzen, nicht nur drei. Ein Objekt
*             ohne 'note' erbte sonst den Hinweis des vorigen - das ist
*             heute folgenlos, weil der Renderer immer alle schreibt,
*             aber es ist eine Falle, die auf ihren Tag wartet.
              CLEAR: lv_otype, lv_oname, lv_otcod,
                     lv_ofilt, lv_onote, lv_optyp, lv_opnam.
              LOOP AT lt_attr INTO lo_attr.
                CASE lo_attr->qname-name.
                  WHEN 'type'.    lv_otype = lo_attr->get_value( ).
                  WHEN 'name'.    lv_oname = lo_attr->get_value( ).
                  WHEN 'tcode'.   lv_otcod = lo_attr->get_value( ).
                  WHEN 'filter'.  lv_ofilt = lo_attr->get_value( ).
                  WHEN 'note'.    lv_onote = lo_attr->get_value( ).
                  WHEN 'objtype'. lv_optyp = lo_attr->get_value( ).
                  WHEN 'objname'. lv_opnam = lo_attr->get_value( ).
                ENDCASE.
              ENDLOOP.
              lo_object = NEW lcl_object( iv_type  = lv_otype
                                          iv_name  = lv_oname
                                          iv_tcode = lv_otcod ).
              lo_object->set_object( iv_objtype = lv_optyp
                                     iv_objname = lv_opnam ).
              lo_object->set_filter( lv_ofilt ).
              lo_object->set_note( lv_onote ).
              CLEAR: lv_ofilt, lv_onote.
              IF lo_current IS BOUND.
                lo_current->add_object( lo_object ).
              ENDIF.

            WHEN 'transport'.
              DATA ls_tr TYPE ty_transport.
              CLEAR ls_tr.
              LOOP AT lt_attr INTO lo_attr.
                CASE lo_attr->qname-name.
                  WHEN 'trkorr'. ls_tr-trkorr = lo_attr->get_value( ).
                  WHEN 'user'.   ls_tr-user   = lo_attr->get_value( ).
                  WHEN 'date'.   ls_tr-date   = lo_attr->get_value( ).
                  WHEN 'text'.   ls_tr-text   = lo_attr->get_value( ).
                ENDCASE.
              ENDLOOP.
              IF lo_object IS BOUND.
                lo_object->add_transport( ls_tr ).
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

            WHEN 'data'.
              LOOP AT lt_attr INTO lo_attr.
                CASE lo_attr->qname-name.
                  WHEN 'row_count'.
                    IF lo_object IS BOUND.
                      lo_object->set_row_count( CONV i( lo_attr->get_value( ) ) ).
                    ENDIF.
                  WHEN 'truncated'.
                    IF lo_object IS BOUND AND lo_attr->get_value( ) = 'true'.
                      lo_object->set_truncated( abap_true ).
                    ENDIF.
                ENDCASE.
              ENDLOOP.

            WHEN 'row'.
              CLEAR ls_row.

            WHEN 'f'.
              CLEAR ls_cell.
              LOOP AT lt_attr INTO lo_attr.
                IF lo_attr->qname-name = 'n'.
                  ls_cell-name = lo_attr->get_value( ).
                ENDIF.
              ENDLOOP.
              lv_target = 'cell'.

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
              WHEN 'cell'.       ls_cell-value      = lv_value.
              WHEN 'node_limit'. ls_meta-node_limit = CONV i( lv_value ).
              WHEN 'node_total'. ls_meta-node_total = CONV i( lv_value ).
              WHEN 'truncated'.
                IF lv_value = 'true'.
                  ls_meta-truncated = abap_true.
                ENDIF.
              WHEN 'title'.
                IF lo_current IS BOUND.
                  lo_current->set_title( lv_value ).
                ENDIF.
              WHEN 'documentation'.
                IF lo_current IS BOUND.
                  lo_current->set_documentation( lv_value ).
                ENDIF.
              WHEN 'projectmemo'.
                IF lo_current IS BOUND.
                  DATA(ls_prm) = lo_current->get_project( ).
                  ls_prm-memo = lv_value.
                  lo_current->set_project( ls_prm ).
                ENDIF.
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
            WHEN 'f'.
              APPEND ls_cell TO ls_row-cells.
            WHEN 'row'.
              IF lo_object IS BOUND.
                lo_object->add_row( ls_row ).
              ENDIF.
            WHEN 'object'.
              CLEAR lo_object.
          ENDCASE.

          CLEAR lv_target.

      ENDCASE.

    ENDDO.

    ro_document->set_meta( ls_meta ).

  ENDMETHOD.

ENDCLASS.


*----------------------------------------------------------------------*
* Selektionsbild
*
* Die gv_* Felder entstehen implizit aus SELECTION-SCREEN COMMENT und
* FRAME TITLE und duerfen nicht zusaetzlich per DATA deklariert werden.
*----------------------------------------------------------------------*

* Der zuletzt selbst gebildete Dateinamensvorschlag. Nur solange im Feld
* genau dieser Wert steht, darf der naechste Bildaufbau ihn ersetzen.
DATA gv_fauto TYPE char128.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE gv_blk1.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tmode FOR FIELD p_mode.
*   V = eine oder mehrere Pruefvarianten, K = der ganze Katalog der
*   aktivierten Checks. Der Katalog beantwortet "was koennte geprueft
*   werden", die Variante "was wird geprueft".
    PARAMETERS p_mode TYPE char1 DEFAULT 'V'.
    SELECTION-SCREEN COMMENT 38(40) gv_tmodt.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tvar FOR FIELD p_var.
    PARAMETERS p_var TYPE sci_chkv DEFAULT 'DEFAULT'.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tvusr FOR FIELD p_vusr.
*   Leer heisst globale Variante. Der Code Inspector fuehrt persoenliche
*   Varianten unter dem Namen ihres Eigentuemers.
    PARAMETERS p_vusr TYPE sci_user.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tallv FOR FIELD p_allv.
    PARAMETERS p_allv AS CHECKBOX.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_thide FOR FIELD p_hide.
    PARAMETERS p_hide AS CHECKBOX.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE gv_blk2.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tlang FOR FIELD p_langu.
    PARAMETERS p_langu TYPE sy-langu DEFAULT sy-langu.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tmsg FOR FIELD p_msg.
    PARAMETERS p_msg AS CHECKBOX DEFAULT 'X'.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tprio FOR FIELD p_prio.
    PARAMETERS p_prio AS CHECKBOX DEFAULT 'X'.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tpcom FOR FIELD p_pcom.
    PARAMETERS p_pcom AS CHECKBOX DEFAULT 'X'.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_texmp FOR FIELD p_exmp.
    PARAMETERS p_exmp AS CHECKBOX.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tcat FOR FIELD p_cat.
    PARAMETERS p_cat AS CHECKBOX DEFAULT 'X'.
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

INITIALIZATION.
* Textelemente sind ein eigener Programmbestandteil und kommen beim
* Kopieren des Quelltextes nicht mit. Die Beschriftungen stehen deshalb
* hier im Quelltext.
  IF sy-langu = 'D'.
    gv_blk1  = 'Auswahl'.
    gv_tmode = 'Modus (V Variante, K Katalog)'.
    gv_tvar  = 'Pruefvariante'.
    gv_tvusr = 'Eigentuemer (leer = global)'.
    gv_tallv = 'Alle Varianten'.
    gv_thide = 'Versteckte einbeziehen'.
    gv_blk2  = 'Umfang'.
    gv_tlang = 'Ausgabesprache'.
    gv_tmsg  = 'Meldungen je Check'.
    gv_tprio = 'Kundenpriorisierung ausweisen'.
    gv_tpcom = 'Pseudokommentar und Pragma'.
    gv_texmp = 'Erteilte Ausnahmen zaehlen'.
    gv_tcat  = 'Nach Kategorie gliedern'.
    gv_blk3  = 'Ausgabe'.
    gv_txml  = 'XML erzeugen/ausgeben'.
    gv_thtml = 'HTML erzeugen/anzeigen'.
    gv_tfold = 'HTML einklappen ab Zeilen'.
    gv_trt   = 'Roundtrip pruefen'.
    gv_tdown = 'Download auf PC'.
    gv_tpath = 'Verzeichnis'.
    gv_tfnam = 'Dateiname (ohne Endung)'.
    gv_tdsrv = 'Ablage Appl.-Server'.
    gv_tsrv  = 'Verzeichnis'.
  ELSE.
    gv_blk1  = 'Selection'.
    gv_tmode = 'Mode (V variant, K catalog)'.
    gv_tvar  = 'Check variant'.
    gv_tvusr = 'Owner (empty = global)'.
    gv_tallv = 'All variants'.
    gv_thide = 'Include hidden ones'.
    gv_blk2  = 'Scope'.
    gv_tlang = 'Output language'.
    gv_tmsg  = 'Messages per check'.
    gv_tprio = 'Show customer priorities'.
    gv_tpcom = 'Pseudo comment and pragma'.
    gv_texmp = 'Count granted exemptions'.
    gv_tcat  = 'Group by category'.
    gv_blk3  = 'Output'.
    gv_txml  = 'Create/display XML'.
    gv_thtml = 'Create/display HTML'.
    gv_tfold = 'Collapse HTML from lines'.
    gv_trt   = 'Check roundtrip'.
    gv_tdown = 'Download to PC'.
    gv_tpath = 'Directory'.
    gv_tfnam = 'File name (no extension)'.
    gv_tdsrv = 'Store on app server'.
    gv_tsrv  = 'Directory'.
  ENDIF.

AT SELECTION-SCREEN OUTPUT.
  PERFORM mode_text.
  PERFORM suggest_fname.
  PERFORM screen_mode.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_path.
  PERFORM f4_verzeichnis.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_var.
  PERFORM f4_variante.

AT SELECTION-SCREEN.
  IF sy-ucomm = 'ONLI' OR sy-ucomm = 'SJOB' OR sy-ucomm = 'PRIN'.
    IF p_mode = 'V' AND p_allv = abap_false AND p_var IS INITIAL.
      MESSAGE lcl_t=>ui( d = `Bitte eine Pruefvariante angeben.`
                         e = `Please enter a check variant.` ) TYPE 'E'.
    ENDIF.
  ENDIF.

*----------------------------------------------------------------------*
* lcl_collector_atc
*
* Sammelt die Pruefkonfiguration in dasselbe Kapitelmodell, das die
* beiden anderen Reports benutzen.
*
* Gliederung:
*   Kapitel 1..n   je Pruefvariante
*     Kapitel n.m  je Kategorie (abschaltbar)
*       Kapitel     je Check, mit einem Objekt fuer die Meldungen
*
* Im Katalogmodus entfaellt die Variantenebene: dann steht der ganze
* Bestand aktivierter Checks unter einem Kapitel.
*----------------------------------------------------------------------*
CLASS lcl_collector_atc DEFINITION.
  PUBLIC SECTION.
    INTERFACES lif_docu_collector.
    METHODS constructor
      IMPORTING iv_mode  TYPE char1
                iv_var   TYPE sci_chkv
                iv_vusr  TYPE sci_user
                iv_allv  TYPE abap_bool
                iv_hide  TYPE abap_bool
                iv_langu TYPE sy-langu
                iv_msg   TYPE abap_bool
                iv_prio  TYPE abap_bool
                iv_pcom  TYPE abap_bool
                iv_exmp  TYPE abap_bool
                iv_cat   TYPE abap_bool.
    METHODS get_stat_variants RETURNING VALUE(rv_n) TYPE i.
    METHODS get_stat_checks   RETURNING VALUE(rv_n) TYPE i.
    METHODS get_stat_messages RETURNING VALUE(rv_n) TYPE i.
    METHODS get_stat_custom   RETURNING VALUE(rv_n) TYPE i.
    METHODS get_stat_broken   RETURNING VALUE(rv_n) TYPE i.
  PRIVATE SECTION.
*   Nicht SCI_CHKS: das ist eine Hash-Tabelle, an die sich nichts
*   anhaengen laesst und ueber die kein Index laeuft.
    TYPES ty_chks TYPE STANDARD TABLE OF sci_chk WITH EMPTY KEY.

    TYPES: BEGIN OF ty_var,
             id     TYPE sci_id,
             user   TYPE sci_user,
             name   TYPE sci_chkv,
             text   TYPE string,
             hidden TYPE abap_bool,
             trans  TYPE abap_bool,
           END OF ty_var.
    TYPES ty_vars TYPE STANDARD TABLE OF ty_var WITH EMPTY KEY.

    TYPES: BEGIN OF ty_prio,
             test TYPE sci_chk,
             code TYPE sci_errc,
             prio TYPE sci_errty,
           END OF ty_prio.

    DATA mv_mode  TYPE char1.
    DATA mv_var   TYPE sci_chkv.
    DATA mv_vusr  TYPE sci_user.
    DATA mv_allv  TYPE abap_bool.
    DATA mv_hide  TYPE abap_bool.
    DATA mv_langu TYPE sy-langu.
    DATA mv_msg   TYPE abap_bool.
    DATA mv_prio  TYPE abap_bool.
    DATA mv_pcom  TYPE abap_bool.
    DATA mv_exmp  TYPE abap_bool.
    DATA mv_cat   TYPE abap_bool.

    DATA mv_n_var TYPE i.
    DATA mv_n_chk TYPE i.
    DATA mv_n_msg TYPE i.
    DATA mv_n_cus TYPE i.
    DATA mv_n_bad TYPE i.

*   Die kundeneigene Priorisierung wird einmal gelesen und im
*   Hauptspeicher gehalten. Ein SELECT SINGLE je Meldung waeren bei
*   einem vollstaendigen Katalog mehrere tausend Zugriffe.
    DATA mt_prio TYPE SORTED TABLE OF ty_prio WITH UNIQUE KEY test code.
    DATA mt_exmp TYPE SORTED TABLE OF ty_prio WITH NON-UNIQUE KEY test code.

    METHODS variants   RETURNING VALUE(rt_vars) TYPE ty_vars.
    METHODS read_prio.
    METHODS read_exmp.
    METHODS variant_chapter
      IMPORTING is_var            TYPE ty_var
                iv_id             TYPE string
      RETURNING VALUE(ro_chapter) TYPE REF TO lcl_chapter.
    METHODS catalog_chapter
      IMPORTING iv_id             TYPE string
      RETURNING VALUE(ro_chapter) TYPE REF TO lcl_chapter.
    METHODS fill_checks
      IMPORTING io_parent TYPE REF TO lcl_chapter
                it_tests  TYPE ty_chks
                iv_id     TYPE string.
    METHODS check_chapter
      IMPORTING iv_test           TYPE sci_chk
                iv_id             TYPE string
      RETURNING VALUE(ro_chapter) TYPE REF TO lcl_chapter.
    METHODS test_ref
      IMPORTING iv_test        TYPE sci_chk
      RETURNING VALUE(ro_test) TYPE REF TO cl_ci_test_root.
    METHODS prio_text
      IMPORTING iv_kind        TYPE clike
      RETURNING VALUE(rv_text) TYPE string.
    METHODS cat_text
      IMPORTING iv_cat         TYPE clike
      RETURNING VALUE(rv_text) TYPE string.
ENDCLASS.

CLASS lcl_collector_atc IMPLEMENTATION.

  METHOD constructor.
    mv_mode  = iv_mode.
    mv_var   = iv_var.
    mv_vusr  = iv_vusr.
    mv_allv  = iv_allv.
    mv_hide  = iv_hide.
    mv_langu = iv_langu.
    mv_msg   = iv_msg.
    mv_prio  = iv_prio.
    mv_pcom  = iv_pcom.
    mv_exmp  = iv_exmp.
    mv_cat   = iv_cat.
  ENDMETHOD.

  METHOD get_stat_variants.
    rv_n = mv_n_var.
  ENDMETHOD.
  METHOD get_stat_checks.
    rv_n = mv_n_chk.
  ENDMETHOD.
  METHOD get_stat_messages.
    rv_n = mv_n_msg.
  ENDMETHOD.
  METHOD get_stat_custom.
    rv_n = mv_n_cus.
  ENDMETHOD.
  METHOD get_stat_broken.
    rv_n = mv_n_bad.
  ENDMETHOD.

  METHOD lif_docu_collector~collect.

    ro_document = NEW lcl_document( ).

    IF mv_prio = abap_true.
      read_prio( ).
    ENDIF.
    IF mv_exmp = abap_true.
      read_exmp( ).
    ENDIF.

    IF mv_mode = 'K'.
      ro_document->add_chapter( catalog_chapter( '1' ) ).
    ELSE.
      DATA lv_no TYPE i.
      LOOP AT variants( ) INTO DATA(ls_var).
        lv_no = lv_no + 1.
        DATA(lo_chap) = variant_chapter( is_var = ls_var
                                         iv_id  = |{ lv_no }| ).
        IF lo_chap IS BOUND.
          ro_document->add_chapter( lo_chap ).
        ENDIF.
      ENDLOOP.
    ENDIF.

    DATA ls_meta TYPE ty_meta.
    ls_meta-version    = gc_version.
    ls_meta-doc_type   = 'ATC'.
    ls_meta-system     = sy-sysid.
    ls_meta-client     = sy-mandt.
    ls_meta-created_by = sy-uname.
    ls_meta-created_at = |{ sy-datum DATE = ISO } { sy-uzeit TIME = ISO }|.
    ls_meta-language   = mv_langu.
    ls_meta-node_total = mv_n_chk.
    ro_document->set_meta( ls_meta ).

  ENDMETHOD.

  METHOD variants.

*   Die Kopfsaetze stehen lesbar in der Datenbank, die Checkliste nicht -
*   SCICHKV_PA ist ein INDX-Cluster. Ausgewaehlt wird hier, gelesen wird
*   spaeter ueber die API.
    DATA lt_hd TYPE STANDARD TABLE OF scichkv_hd WITH EMPTY KEY.

    IF mv_allv = abap_true.
      SELECT * FROM scichkv_hd INTO TABLE @lt_hd.
    ELSE.
      SELECT * FROM scichkv_hd
        WHERE checkvname = @mv_var AND ciuser = @mv_vusr
        INTO TABLE @lt_hd.
    ENDIF.

    SORT lt_hd BY ciuser checkvname.
    LOOP AT lt_hd INTO DATA(ls_hd).

      IF ls_hd-hidden = abap_true AND mv_hide = abap_false.
        CONTINUE.
      ENDIF.

      SELECT SINGLE text FROM scichkv_tx
        WHERE language = @mv_langu AND checkvid = @ls_hd-checkvid
          AND ciuser = @ls_hd-ciuser
        INTO @DATA(lv_text).
      IF sy-subrc <> 0.
        SELECT SINGLE text FROM scichkv_tx
          WHERE checkvid = @ls_hd-checkvid AND ciuser = @ls_hd-ciuser
          INTO @lv_text.
      ENDIF.

      APPEND VALUE ty_var( id     = ls_hd-checkvid
                           user   = ls_hd-ciuser
                           name   = ls_hd-checkvname
                           text   = lv_text
                           hidden = ls_hd-hidden
                           trans  = ls_hd-transport ) TO rt_vars.
    ENDLOOP.

  ENDMETHOD.

  METHOD read_prio.

*   SCIPRIORITIES traegt nur die Abweichungen. Was hier nicht steht,
*   laeuft mit der Prioritaet, die die Checkklasse selbst vergibt.
    SELECT checkname, checkcode, custom_prio FROM scipriorities
      INTO TABLE @DATA(lt_p).
    LOOP AT lt_p INTO DATA(ls_p).
      INSERT VALUE ty_prio( test = ls_p-checkname
                            code = ls_p-checkcode
                            prio = ls_p-custom_prio ) INTO TABLE mt_prio.
    ENDLOOP.

  ENDMETHOD.

  METHOD read_exmp.

*   Erteilte Ausnahmen. Geloeschte bleiben in der Tabelle stehen und
*   werden hier weggelassen; auf den Genehmigungsstand wird bewusst
*   nicht gefiltert, weil dessen Schluessel zwischen Staenden wechselt -
*   gezaehlt wird also "es gibt eine Ausnahme dazu", nicht "sie ist
*   genehmigt". Das Dokument sagt es so.
    SELECT chkclass, chkcode FROM satc_ci_exempt
      WHERE deleted <> @abap_true
      INTO TABLE @DATA(lt_e).
    LOOP AT lt_e INTO DATA(ls_e).
      INSERT VALUE ty_prio( test = ls_e-chkclass
                            code = ls_e-chkcode ) INTO TABLE mt_exmp.
    ENDLOOP.

  ENDMETHOD.

  METHOD variant_chapter.

    DATA lo_ref   TYPE REF TO cl_ci_checkvariant.
    DATA lt_tests TYPE ty_chks.

    CALL METHOD cl_ci_checkvariant=>get_ref
      EXPORTING  p_user          = is_var-user
                 p_name          = is_var-name
      RECEIVING  p_ref           = lo_ref
      EXCEPTIONS chkv_not_exists = 1
                 missing_parameter = 2
                 broken_variant  = 3
                 OTHERS          = 4.
    IF sy-subrc <> 0 OR lo_ref IS NOT BOUND.
      mv_n_bad = mv_n_bad + 1.
      RETURN.
    ENDIF.

    CALL METHOD lo_ref->get_info
      EXCEPTIONS could_not_read_variant = 1
                 OTHERS                 = 2.
    IF sy-subrc <> 0.
      mv_n_bad = mv_n_bad + 1.
      RETURN.
    ENDIF.

    mv_n_var = mv_n_var + 1.

    DATA(lv_title) = |{ is_var-name }|.
    IF is_var-text IS NOT INITIAL.
      lv_title = |{ lv_title } - { is_var-text }|.
    ENDIF.

    ro_chapter = NEW lcl_chapter( iv_id    = iv_id
                                  iv_level = 1
                                  iv_type  = 'VARIANT'
                                  iv_title = lv_title ).
    ro_chapter->set_doclang( CONV string( mv_langu ) ).

*   Die Kopfdaten der Variante als eigenes Objekt: Eigentuemer,
*   Transportierbarkeit und Sichtbarkeit gehoeren zur Aussage
*   "welche Regeln gelten hier" dazu.
    DATA(lo_head) = NEW lcl_object( iv_type = 'VARIANT'
                                    iv_name = CONV string( is_var-name ) ).
    lo_head->add_field( VALUE #( name = lcl_t=>t( d = 'Merkmal' e = 'Property' ) ) ).
    lo_head->add_field( VALUE #( name = lcl_t=>t( d = 'Wert' e = 'Value' ) ) ).

    DATA lt_kv TYPE ty_cells.
    DATA(lv_k) = lcl_t=>t( d = 'Merkmal' e = 'Property' ).
    DATA(lv_v) = lcl_t=>t( d = 'Wert' e = 'Value' ).

    CLEAR lt_kv.
    APPEND VALUE ty_cell( name = lv_k
                          value = lcl_t=>t( d = 'Eigentuemer' e = 'Owner' ) ) TO lt_kv.
    APPEND VALUE ty_cell( name = lv_v
                          value = COND string( WHEN is_var-user IS INITIAL
                                               THEN lcl_t=>t( d = 'global' e = 'global' )
                                               ELSE CONV string( is_var-user ) ) ) TO lt_kv.
    lo_head->add_row( VALUE ty_row( cells = lt_kv ) ).

    CLEAR lt_kv.
    APPEND VALUE ty_cell( name = lv_k
                          value = lcl_t=>t( d = 'Transportierbar' e = 'Transportable' ) ) TO lt_kv.
    APPEND VALUE ty_cell( name = lv_v
                          value = COND string( WHEN is_var-trans = abap_true THEN `X` ) ) TO lt_kv.
    lo_head->add_row( VALUE ty_row( cells = lt_kv ) ).

    CLEAR lt_kv.
    APPEND VALUE ty_cell( name = lv_k
                          value = lcl_t=>t( d = 'Versteckt' e = 'Hidden' ) ) TO lt_kv.
    APPEND VALUE ty_cell( name = lv_v
                          value = COND string( WHEN is_var-hidden = abap_true THEN `X` ) ) TO lt_kv.
    lo_head->add_row( VALUE ty_row( cells = lt_kv ) ).

    CLEAR lt_kv.
    APPEND VALUE ty_cell( name = lv_k
                          value = lcl_t=>t( d = 'Checks in der Variante'
                                            e = 'Checks in the variant' ) ) TO lt_kv.
    APPEND VALUE ty_cell( name = lv_v
                          value = |{ lines( lo_ref->variant ) }| ) TO lt_kv.
    lo_head->add_row( VALUE ty_row( cells = lt_kv ) ).

    ro_chapter->add_object( lo_head ).

    LOOP AT lo_ref->variant INTO DATA(ls_tv).
      APPEND ls_tv-testname TO lt_tests.
    ENDLOOP.

    fill_checks( io_parent = ro_chapter
                 it_tests  = lt_tests
                 iv_id     = iv_id ).

  ENDMETHOD.

  METHOD catalog_chapter.

    DATA lt_act   TYPE sci_actchks.
    DATA lt_tests TYPE ty_chks.

    CALL METHOD cl_ci_tests=>get_tests
      EXPORTING  p_active_tests     = abap_true
      IMPORTING  p_tests            = lt_act
      EXCEPTIONS invalid_class_name = 1
                 test_not_exists    = 2
                 transport_error    = 3
                 no_destination     = 4
                 invalid_destination = 5
                 no_remote_check    = 6
                 OTHERS             = 7.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    LOOP AT lt_act INTO DATA(ls_act).
      IF ls_act-ref IS BOUND.
        APPEND ls_act-ref->name TO lt_tests.
      ENDIF.
    ENDLOOP.
*   Der Zeilentyp ist elementar; sortiert und entdoppelt wird deshalb
*   ueber TABLE_LINE, nicht ueber einen Feldnamen.
    SORT lt_tests BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_tests COMPARING table_line.

    ro_chapter = NEW lcl_chapter(
      iv_id    = iv_id
      iv_level = 1
      iv_type  = 'CATALOG'
      iv_title = |{ lcl_t=>t( d = 'Aktivierte Checks' e = 'Activated checks' ) } | &&
                 |({ lines( lt_tests ) })| ).
    ro_chapter->set_doclang( CONV string( mv_langu ) ).

    fill_checks( io_parent = ro_chapter
                 it_tests  = lt_tests
                 iv_id     = iv_id ).

  ENDMETHOD.

  METHOD fill_checks.

    TYPES: BEGIN OF ty_grp,
             cat   TYPE string,
             text  TYPE string,
             tests TYPE ty_chks,
           END OF ty_grp.
    DATA lt_grp TYPE STANDARD TABLE OF ty_grp WITH EMPTY KEY.

    LOOP AT it_tests INTO DATA(lv_test).

      DATA(lo_test) = test_ref( lv_test ).
      DATA lv_cat TYPE string.
      CLEAR lv_cat.
      IF mv_cat = abap_true AND lo_test IS BOUND.
        lv_cat = lo_test->category.
      ENDIF.

      READ TABLE lt_grp ASSIGNING FIELD-SYMBOL(<ls_grp>)
           WITH KEY cat = lv_cat.
      IF sy-subrc <> 0.
        APPEND VALUE ty_grp( cat  = lv_cat
                             text = cat_text( lv_cat ) ) TO lt_grp
               ASSIGNING <ls_grp>.
      ENDIF.
      APPEND lv_test TO <ls_grp>-tests.

    ENDLOOP.

    SORT lt_grp BY text cat.

    DATA lv_g TYPE i.
    LOOP AT lt_grp INTO DATA(ls_grp).

      DATA(lo_under) = io_parent.
      DATA lv_pre TYPE string.
      lv_pre = iv_id.

      IF mv_cat = abap_true.
        lv_g = lv_g + 1.
        lv_pre = |{ iv_id }.{ lv_g }|.
        lo_under = NEW lcl_chapter(
          iv_id    = lv_pre
          iv_level = 2
          iv_type  = 'CATEGORY'
          iv_title = |{ ls_grp-text } ({ lines( ls_grp-tests ) })| ).
        lo_under->set_doclang( CONV string( mv_langu ) ).
        io_parent->add_child( lo_under ).
      ENDIF.

      DATA lv_c TYPE i.
      CLEAR lv_c.
      SORT ls_grp-tests BY table_line.
      LOOP AT ls_grp-tests INTO DATA(lv_t).
        lv_c = lv_c + 1.
        DATA(lo_chk) = check_chapter( iv_test = lv_t
                                      iv_id   = |{ lv_pre }.{ lv_c }| ).
        IF lo_chk IS BOUND.
          lo_under->add_child( lo_chk ).
        ENDIF.
      ENDLOOP.

    ENDLOOP.

  ENDMETHOD.

  METHOD check_chapter.

    DATA(lo_test) = test_ref( iv_test ).
    IF lo_test IS NOT BOUND.
*     Eine Variante kann einen Check nennen, den es hier nicht mehr
*     gibt - nach einem Upgrade der Normalfall. Das Kapitel entsteht
*     trotzdem, sonst verschwiegen wir eine Luecke in der Konfiguration.
      mv_n_bad = mv_n_bad + 1.
      ro_chapter = NEW lcl_chapter(
        iv_id    = iv_id
        iv_level = COND #( WHEN mv_cat = abap_true THEN 3 ELSE 2 )
        iv_type  = 'CHECK'
        iv_title = |{ iv_test } - { lcl_t=>t( d = 'nicht ladbar' e = 'cannot be loaded' ) }| ).
      ro_chapter->set_doclang( CONV string( mv_langu ) ).
      RETURN.
    ENDIF.

    mv_n_chk = mv_n_chk + 1.

    DATA(lv_title) = |{ iv_test }|.
    IF lo_test->description IS NOT INITIAL.
      lv_title = |{ lv_title } - { lo_test->description }|.
    ENDIF.

    ro_chapter = NEW lcl_chapter(
      iv_id    = iv_id
      iv_level = COND #( WHEN mv_cat = abap_true THEN 3 ELSE 2 )
      iv_type  = 'CHECK'
      iv_title = lv_title ).
    ro_chapter->set_doclang( CONV string( mv_langu ) ).

    IF mv_msg = abap_false.
      RETURN.
    ENDIF.

    DATA(lo_obj) = NEW lcl_object( iv_type = 'CHECK'
                                   iv_name = CONV string( iv_test ) ).

    DATA(lv_c_code) = lcl_t=>t( d = 'Code' e = 'Code' ).
    DATA(lv_c_prio) = lcl_t=>t( d = 'Prioritaet' e = 'Priority' ).
    DATA(lv_c_cust) = lcl_t=>t( d = 'Kundenprio' e = 'Customer prio' ).
    DATA(lv_c_pcom) = lcl_t=>t( d = 'Pseudokommentar' e = 'Pseudo comment' ).
    DATA(lv_c_prag) = lcl_t=>t( d = 'Pragma' e = 'Pragma' ).
    DATA(lv_c_exmp) = lcl_t=>t( d = 'Ausnahmen' e = 'Exemptions' ).
    DATA(lv_c_text) = lcl_t=>t( d = 'Text' e = 'Text' ).

    lo_obj->add_field( VALUE #( name = lv_c_code ) ).
    lo_obj->add_field( VALUE #( name = lv_c_prio ) ).
    IF mv_prio = abap_true.
      lo_obj->add_field( VALUE #( name = lv_c_cust ) ).
    ENDIF.
    IF mv_pcom = abap_true.
      lo_obj->add_field( VALUE #( name = lv_c_pcom ) ).
      lo_obj->add_field( VALUE #( name = lv_c_prag ) ).
    ENDIF.
    IF mv_exmp = abap_true.
      lo_obj->add_field( VALUE #( name = lv_c_exmp ) ).
    ENDIF.
    lo_obj->add_field( VALUE #( name = lv_c_text ) ).

    DATA lt_cells TYPE ty_cells.
    DATA lv_mtext TYPE string.

    LOOP AT lo_test->scimessages INTO DATA(ls_msg).

      mv_n_msg = mv_n_msg + 1.
      CLEAR lt_cells.

      APPEND VALUE ty_cell( name = lv_c_code value = ls_msg-code ) TO lt_cells.
      APPEND VALUE ty_cell( name = lv_c_prio
                            value = prio_text( ls_msg-kind ) ) TO lt_cells.

      IF mv_prio = abap_true.
        READ TABLE mt_prio INTO DATA(ls_prio)
             WITH TABLE KEY test = iv_test code = ls_msg-code.
        IF sy-subrc = 0.
          mv_n_cus = mv_n_cus + 1.
          APPEND VALUE ty_cell( name = lv_c_cust
                                value = prio_text( ls_prio-prio ) ) TO lt_cells.
        ELSE.
          APPEND VALUE ty_cell( name = lv_c_cust value = '' ) TO lt_cells.
        ENDIF.
      ENDIF.

      IF mv_pcom = abap_true.
        APPEND VALUE ty_cell( name = lv_c_pcom
                              value = ls_msg-pcom ) TO lt_cells.
        APPEND VALUE ty_cell( name = lv_c_prag
                              value = ls_msg-pragma ) TO lt_cells.
      ENDIF.

      IF mv_exmp = abap_true.
        DATA lv_cnt TYPE i.
        CLEAR lv_cnt.
        LOOP AT mt_exmp TRANSPORTING NO FIELDS
             WHERE test = iv_test AND code = ls_msg-code.
          lv_cnt = lv_cnt + 1.
        ENDLOOP.
        APPEND VALUE ty_cell( name = lv_c_exmp
                              value = COND string( WHEN lv_cnt > 0
                                                   THEN |{ lv_cnt }| ) ) TO lt_cells.
      ENDIF.

*     Der Text der Meldung steht nicht in SCIMESSAGE selbst, sondern
*     wird von der Checkklasse geliefert - sie kennt die Sprache.
      CLEAR lv_mtext.
      cl_ci_tests=>get_message_text( EXPORTING p_test = iv_test
                                               p_code = ls_msg-code
                                     IMPORTING p_text = lv_mtext ).
      IF lv_mtext IS INITIAL.
        lv_mtext = ls_msg-text.
      ENDIF.
      APPEND VALUE ty_cell( name = lv_c_text value = lv_mtext ) TO lt_cells.

      lo_obj->add_row( VALUE ty_row( cells = lt_cells ) ).

    ENDLOOP.

    lo_obj->set_row_count( lines( lo_test->scimessages ) ).

    DATA lv_note TYPE string.
    lv_note = |{ lcl_t=>t( d = 'Version' e = 'Version' ) } { lo_test->version }|.
    IF lo_test->has_attributes = abap_true.
      lv_note = |{ lv_note }, { lcl_t=>t( d = 'mit eigenen Einstellungen'
                                          e = 'with its own settings' ) }|.
    ENDIF.
    IF lo_test->remote_enabled = abap_true.
      lv_note = |{ lv_note }, { lcl_t=>t( d = 'remotefaehig'
                                          e = 'remote enabled' ) }|.
    ENDIF.
    lo_obj->set_note( lv_note ).

    ro_chapter->add_object( lo_obj ).

  ENDMETHOD.

  METHOD test_ref.

*   GET_TEST_REF meldet einen unbekannten Check nicht, sondern gibt eine
*   initiale Referenz zurueck - das steht so in der Dokumentation der
*   Methode. Der Aufrufer muss also selbst pruefen.
    CALL METHOD cl_ci_tests=>get_test_ref
      EXPORTING  p_test              = iv_test
      RECEIVING  p_result            = ro_test
      EXCEPTIONS invalid_version     = 1
                 invalid_destination = 2
                 OTHERS              = 3.
    IF sy-subrc <> 0.
      CLEAR ro_test.
    ENDIF.

  ENDMETHOD.

  METHOD prio_text.

    CASE iv_kind.
      WHEN 'E'. rv_text = lcl_t=>t( d = 'Fehler' e = 'Error' ).
      WHEN 'W'. rv_text = lcl_t=>t( d = 'Warnung' e = 'Warning' ).
      WHEN 'N'. rv_text = lcl_t=>t( d = 'Hinweis' e = 'Note' ).
      WHEN OTHERS. rv_text = iv_kind.
    ENDCASE.

  ENDMETHOD.

  METHOD cat_text.

    IF iv_cat IS INITIAL.
      rv_text = lcl_t=>t( d = 'Ohne Kategorie' e = 'Without category' ).
      RETURN.
    ENDIF.

    DATA(lo_cat) = test_ref( CONV sci_chk( iv_cat ) ).
    IF lo_cat IS BOUND AND lo_cat->description IS NOT INITIAL.
      rv_text = lo_cat->description.
    ELSE.
      rv_text = iv_cat.
    ENDIF.

  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* lcl_renderer_html - readable output from the same chapter model
*
* Deliberately a self-contained file without external dependencies: CSS
* embedded, no JavaScript. The file should still open without any rework
* years from now.
*
* The ITF format keys of the documentation are not evaluated yet, the
* text appears as a preformatted block. Converting it into paragraphs
* and lists belongs to step 6.
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
*   otherwise just the heading above it. rv_folded has to be handed back
*   to close_block so that the tag is closed exactly when it was opened.
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
    METHODS itf_to_html   IMPORTING iv_text TYPE string
                          RETURNING VALUE(rv_html) TYPE string.
    METHODS itf_section   IMPORTING iv_marker TYPE string
                          RETURNING VALUE(rv_label) TYPE string.
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
      lv_unit = lcl_t=>t( d = 'Zeilen' e = 'rows' ).
    ENDIF.

    IF gv_fold > 0 AND iv_count > gv_fold.
*     <details> is plain HTML - the file stays free of JavaScript, and a
*     browser that does not know the element shows the content anyway.
      rv_folded = abap_true.
      add( |<details><summary>{ esc( iv_label ) } | &&
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

  METHOD itf_section.
    " The IMG documentation is divided into fixed sections that appear in
    " the ITF text as &NAME&. They become subheadings.
    CASE iv_marker.
      WHEN 'SHORTTEXT'.      rv_label = lcl_t=>t( d = 'Kurztext' e = 'Short text' ).
      WHEN 'USE'.            rv_label = lcl_t=>t( d = 'Verwendung' e = 'Use' ).
      WHEN 'PRECONDITIONS'.  rv_label = lcl_t=>t( d = 'Voraussetzungen' e = 'Prerequisites' ).
      WHEN 'STANDARD_SETUP'. rv_label = lcl_t=>t( d = 'Standardeinstellungen' e = 'Standard settings' ).
      WHEN 'ACTIVITY'.       rv_label = lcl_t=>t( d = 'Vorgehen' e = 'Activities' ).
      WHEN 'EXAMPLE'.        rv_label = lcl_t=>t( d = 'Beispiel' e = 'Example' ).
      WHEN 'RECOMMENDATION'. rv_label = lcl_t=>t( d = 'Empfehlung' e = 'Recommendation' ).
      WHEN 'CAUTION'.        rv_label = lcl_t=>t( d = 'Achtung' e = 'Caution' ).
      WHEN OTHERS.           rv_label = iv_marker.
    ENDCASE.
  ENDMETHOD.

  METHOD itf_to_html.

    DATA lt_lines TYPE STANDARD TABLE OF string.
    DATA lv_line  TYPE string.
    DATA lv_len   TYPE i.

    SPLIT iv_text AT cl_abap_char_utilities=>newline INTO TABLE lt_lines.

    rv_html = '<div class="doc">'.

    LOOP AT lt_lines INTO lv_line.

      CONDENSE lv_line.

      " SAPscript control statement, no content
      IF lv_line = 'RESET N1'.
        CONTINUE.
      ENDIF.

      IF lv_line IS INITIAL.
        rv_html = |{ rv_html }<p></p>|.
        CONTINUE.
      ENDIF.

      " Section marker &NAME& - becomes a heading, the ampersands
      " disappear in the process.
      "
      " The check uses a regular expression and not CS: the comparison
      " operator ignores trailing blanks in the search operand, which is
      " why "line CS space" is always true.
      lv_len = strlen( lv_line ).
      FIND PCRE '^&[A-Z0-9_]+&$' IN lv_line.
      IF sy-subrc = 0.
        rv_html = |{ rv_html }<p class="sec">{ esc(
                    itf_section( substring( val = lv_line off = 1 len = lv_len - 2 ) ) ) }</p>|.
        CONTINUE.
      ENDIF.

      lv_line = esc( lv_line ).

      " ITF markup. There are more of them than the common three - ZH, LS,
      " ZK, PF, US and others. Instead of maintaining them one by one, all
      " two- to three-character markers are handled generically; cross
      " references <DS:...> are added. All of them are rendered in bold,
      " the closing marker </> applies to every one of them.
      REPLACE ALL OCCURRENCES OF PCRE '&lt;DS:[^&]+&gt;' IN lv_line WITH '<b>'.
      REPLACE ALL OCCURRENCES OF '&lt;/&gt;' IN lv_line WITH '</b>'.
      REPLACE ALL OCCURRENCES OF PCRE '&lt;[A-Z0-9]{2,3}&gt;' IN lv_line WITH '<b>'.

      " Balance the markup per line. In ITF markers also run across line
      " boundaries; without balancing an open marker would style the rest
      " of the document.
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

      " Tabs of the ITF storage format
      REPLACE ALL OCCURRENCES OF ',,' IN lv_line WITH ' '.

      rv_html = |{ rv_html }{ lv_line }<br>|.

    ENDLOOP.

    rv_html = |{ rv_html }</div>|.

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
    add( 'div.proj{background:#eef4ea;border-left:3px solid #6a9a4b;' &&
         'padding:8px;margin:6px 0;font-size:11px}' ).
    add( 'p.memo{margin:4px 0 0 0;white-space:pre-wrap}' ).
    add( 'div.doc p{margin:0 0 6px 0}' ).
    add( '.ref{color:#666;font-size:11px;margin:2px 0}' ).
    add( '.warn{color:#a00;font-weight:bold}' ).
    add( 'ul.toc{line-height:1.6}' ).
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
    add( |<tr><th>Format</th><td>Version { esc( ls_meta-version ) }</td></tr>| ).

    DATA lv_limit TYPE string.
    IF ls_meta-node_limit = 0.
      lv_limit = lcl_t=>t( d = 'ohne Begrenzung' e = 'no limit' ).
    ELSE.
      lv_limit = |{ lcl_t=>t( d = 'Limit' e = 'limit' ) } { ls_meta-node_limit }|.
    ENDIF.
    add( |<tr><th>{ lcl_t=>t( d = 'Kapitel' e = 'Chapters' ) }</th>| &&
         |<td>{ ls_meta-node_total } | &&
         |{ lcl_t=>t( d = 'im gewählten Umfang' e = 'in the selected scope' ) }, | &&
         |{ lv_limit }</td></tr>| ).
    add( '</table>' ).

    IF ls_meta-truncated = abap_true.
      add( |<p class="warn">{ lcl_t=>t(
             d = |Achtung: Von { ls_meta-node_total } Kapiteln im gewählten | &&
                 |Umfang sind nur { ls_meta-node_limit } enthalten. Das | &&
                 |Dokument ist unvollständig.|
             e = |Caution: of { ls_meta-node_total } chapters in the selected | &&
                 |scope only { ls_meta-node_limit } are contained. The | &&
                 |document is incomplete.| ) }</p>| ).
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

  METHOD write_toc.
    " Only the top two levels, otherwise the table of contents grows
    " longer than the document.
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
      add( |<p class="ref">{ lcl_t=>t( d = 'IMG-Aktivität' e = 'IMG activity' ) }| &&
           | { esc( ls_ref-activity ) }| &&
           |, { lcl_t=>t( d = 'Transaktion' e = 'transaction' ) } { esc( ls_ref-tcode ) }| &&
           |, { lcl_t=>t( d = 'Dokuobjekt' e = 'doc object' ) } { esc( ls_ref-docu_id ) }</p>| ).
    ENDIF.

    IF io_chapter->has_project( ) = abap_true.
      DATA(ls_pr) = io_chapter->get_project( ).
      add( |<div class="proj"><b>{ lcl_t=>t( d = 'Projekt' e = 'Project' ) }| &&
           | { esc( ls_pr-project ) }</b>| ).
      IF ls_pr-status IS NOT INITIAL.
        add( | &nbsp; Status { esc( ls_pr-status ) }| &&
             | &nbsp; { lcl_t=>t( d = 'Fortschritt' e = 'progress' ) }| &&
             | { esc( ls_pr-done ) } %| ).
      ENDIF.
      IF ls_pr-memo IS NOT INITIAL.
        add( |<p class="memo">{ esc( ls_pr-memo ) }</p>| ).
      ENDIF.
      add( '</div>' ).
    ENDIF.

    IF io_chapter->get_documentation( ) IS NOT INITIAL.
      add( itf_to_html( io_chapter->get_documentation( ) ) ).
    ENDIF.

    LOOP AT io_chapter->get_objects( ) INTO DATA(lo_obj).

      DATA lv_rows TYPE string.
      IF lo_obj->get_truncated( ) = abap_true.
        lv_rows = |{ lines( lo_obj->get_rows( ) ) } | &&
                  |{ lcl_t=>t( d = 'von' e = 'of' ) } { lo_obj->get_row_count( ) } | &&
                  |{ lcl_t=>t( d = '(gekürzt)' e = '(truncated)' ) }|.
      ELSE.
        lv_rows = |{ lo_obj->get_row_count( ) }|.
      ENDIF.

      add( |<p class="obj"><b>{ esc( lo_obj->get_name( ) ) }</b>| &&
           | &nbsp; { lcl_t=>t( d = 'Typ' e = 'type' ) } { esc( lo_obj->get_type( ) ) }| &&
           | &nbsp; { lcl_t=>t( d = 'Transaktion' e = 'transaction' ) }| &&
           | { esc( lo_obj->get_tcode( ) ) }| &&
           | &nbsp; { lcl_t=>t( d = 'Zeilen' e = 'rows' ) } { lv_rows }| &&
           | &nbsp; { lcl_t=>t( d = 'Auswahl' e = 'selection' ) }| &&
           | { esc( lo_obj->get_filter( ) ) }</p>| ).

      IF lo_obj->get_note( ) IS NOT INITIAL.
*       A note is a warning - except on the reference list, where it is
*       just the heading of the table below it.
        IF lo_obj->get_type( ) = 'CALLS'.
          add( |<p class="ref">{ esc( lo_obj->get_note( ) ) }</p>| ).
        ELSE.
          add( |<p class="warn">{ esc( lo_obj->get_note( ) ) }</p>| ).
        ENDIF.
      ENDIF.

      " Data contents
      IF lines( lo_obj->get_rows( ) ) > 0.
        DATA(lv_fold) = open_block( iv_label = lcl_t=>t( d = 'Tabelleninhalt'
                                                         e = 'Table contents' )
                                    iv_count = lines( lo_obj->get_rows( ) ) ).
        add( '<table><tr>' ).
        LOOP AT lo_obj->get_fields( ) INTO DATA(ls_fh).
          IF ls_fh-keyflag = abap_true.
            add( |<th>{ esc( ls_fh-name ) } *</th>| ).
          ELSE.
            add( |<th>{ esc( ls_fh-name ) }</th>| ).
          ENDIF.
        ENDLOOP.
        add( '</tr>' ).
        LOOP AT lo_obj->get_rows( ) INTO DATA(ls_dr).
          add( '<tr>' ).
          LOOP AT ls_dr-cells INTO DATA(ls_dc).
            add( |<td>{ esc( ls_dc-value ) }</td>| ).
          ENDLOOP.
          add( '</tr>' ).
        ENDLOOP.
        add( '</table>' ).
        close_block( lv_fold ).
      ELSEIF lines( lo_obj->get_fields( ) ) > 0.
        " no data, but the structure is known
        lv_fold = open_block( iv_label = lcl_t=>t( d = 'Feldliste' e = 'Field list' )
                              iv_count = lines( lo_obj->get_fields( ) )
                              iv_unit  = lcl_t=>t( d = 'Felder' e = 'fields' ) ).
        add( |<table><tr><th>{ lcl_t=>t( d = 'Feld' e = 'Field' ) }</th>| &&
             |<th>{ lcl_t=>t( d = 'Datenelement' e = 'Data element' ) }</th>| &&
             |<th>{ lcl_t=>t( d = 'Schlüssel' e = 'Key' ) }</th></tr>| ).
        LOOP AT lo_obj->get_fields( ) INTO DATA(ls_fs).
          add( |<tr><td>{ esc( ls_fs-name ) }</td>| &&
               |<td>{ esc( ls_fs-rollname ) }</td>| &&
               |<td>{ COND string( WHEN ls_fs-keyflag = abap_true THEN 'X' ELSE '' ) }</td></tr>| ).
        ENDLOOP.
        add( '</table>' ).
        close_block( lv_fold ).
      ENDIF.

      " Transport history
      IF lines( lo_obj->get_transports( ) ) > 0.
        lv_fold = open_block( iv_label = lcl_t=>t( d = 'Transport-Historie'
                                                   e = 'Transport history' )
                              iv_count = lines( lo_obj->get_transports( ) )
                              iv_unit  = lcl_t=>t( d = 'Aufträge' e = 'requests' ) ).
        add( |<table><tr><th>{ lcl_t=>t( d = 'Auftrag' e = 'Request' ) }</th>| &&
             |<th>{ lcl_t=>t( d = 'Benutzer' e = 'User' ) }</th>| &&
             |<th>{ lcl_t=>t( d = 'Datum' e = 'Date' ) }</th>| &&
             |<th>{ lcl_t=>t( d = 'Kurztext' e = 'Short text' ) }</th></tr>| ).
        LOOP AT lo_obj->get_transports( ) INTO DATA(ls_th).
          add( |<tr><td>{ esc( ls_th-trkorr ) }</td>| &&
               |<td>{ esc( ls_th-user ) }</td>| &&
               |<td>{ esc( ls_th-date ) }</td>| &&
               |<td>{ esc( ls_th-text ) }</td></tr>| ).
        ENDLOOP.
        add( '</table>' ).
        close_block( lv_fold ).
      ENDIF.

    ENDLOOP.

    LOOP AT io_chapter->get_children( ) INTO DATA(lo_child).
      write_chapter( lo_child ).
    ENDLOOP.

  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
*& FORM mode_text
*&---------------------------------------------------------------------*
FORM mode_text.

  IF p_mode = 'K'.
    gv_tmodt = lcl_t=>ui( d = 'Katalog aller aktivierten Checks'
                          e = 'Catalog of all activated checks' ).
  ELSE.
    gv_tmodt = lcl_t=>ui( d = 'Checks der Pruefvariante'
                          e = 'Checks of the check variant' ).
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM screen_mode
*&---------------------------------------------------------------------*
FORM screen_mode.

* Im Katalogmodus gibt es keine Variante zu waehlen. Die Felder bleiben
* stehen, werden aber inaktiv - ein verschwindendes Feld verwirrt mehr
* als ein graues.
  LOOP AT SCREEN.
    IF screen-name = 'P_VAR' OR screen-name = 'P_VUSR'
       OR screen-name = 'P_ALLV' OR screen-name = 'P_HIDE'.
      IF p_mode = 'K'.
        screen-input = 0.
      ELSE.
        screen-input = 1.
      ENDIF.
      MODIFY SCREEN.
    ENDIF.
*   Eine einzelne Variante und "alle Varianten" schliessen sich aus.
    IF ( screen-name = 'P_VAR' OR screen-name = 'P_VUSR' )
       AND p_allv = abap_true AND p_mode <> 'K'.
      screen-input = 0.
      MODIFY SCREEN.
    ENDIF.
  ENDLOOP.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM f4_variante
*&---------------------------------------------------------------------*
FORM f4_variante.

  TYPES: BEGIN OF ty_pick,
           checkvname TYPE sci_chkv,
           ciuser     TYPE sci_user,
           text       TYPE sci_text,
         END OF ty_pick.
  DATA lt_pick TYPE STANDARD TABLE OF ty_pick WITH EMPTY KEY.
  DATA lt_ret  TYPE STANDARD TABLE OF ddshretval WITH EMPTY KEY.

  SELECT h~checkvname, h~ciuser, t~text
    FROM scichkv_hd AS h
    LEFT OUTER JOIN scichkv_tx AS t
      ON t~checkvid = h~checkvid AND t~ciuser = h~ciuser
     AND t~language = @sy-langu
    WHERE h~hidden = @space
    INTO CORRESPONDING FIELDS OF TABLE @lt_pick.

  SORT lt_pick BY ciuser checkvname.

  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING  retfield        = 'CHECKVNAME'
               dynpprog        = sy-repid
               dynpnr          = sy-dynnr
               dynprofield     = 'P_VAR'
               value_org       = 'S'
    TABLES     value_tab       = lt_pick
               return_tab      = lt_ret
    EXCEPTIONS parameter_error = 1
               no_values_found = 2
               OTHERS          = 3.

ENDFORM.

*----------------------------------------------------------------------*
* Value help for the target directory
*----------------------------------------------------------------------*
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
    WRITE: / lcl_t=>ui( d = `Bitte Verzeichnis auf dem Applikationsserver angeben.` e = `Please specify a directory on the application server.` ).
    RETURN.
  ENDIF.

  lv_dir = p_path.
  SHIFT lv_dir RIGHT DELETING TRAILING space.
  SHIFT lv_dir LEFT  DELETING LEADING space.
  IF lv_dir CA '\'.
    " Add the separator if the directory does not end with one
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

*----------------------------------------------------------------------*
* Store the file on the application server
*
* The route for background processing: frontend services are not
* available there. Writing works as with the PC download, binary in
* UTF-8, so that both destinations produce the same file.
*----------------------------------------------------------------------*
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
*& FORM suggest_fname
*&---------------------------------------------------------------------*
FORM suggest_fname.

* Der Vorschlag wird bei jedem Bildaufbau neu gebildet, damit er der
* Auswahl folgt. Ueberschrieben wird das Feld nur, solange darin noch
* der vorige Vorschlag steht - ein selbst gewaehlter Name bleibt.
  DATA lv_new  TYPE string.
  DATA lv_part TYPE string.

  PERFORM fname_object CHANGING lv_part.
  lv_new = |documizer_atc_{ sy-sysid }{ lv_part }_{ sy-datum }_{ sy-uzeit }|.

  IF p_fname IS INITIAL OR p_fname = gv_fauto.
    p_fname = lv_new.
  ENDIF.
  gv_fauto = lv_new.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM fname_object
*&---------------------------------------------------------------------*
FORM fname_object CHANGING cv_part TYPE string.

  DATA lv_name TYPE string.

  CLEAR cv_part.
  IF p_mode = 'K'.
    cv_part = `_katalog`.
    RETURN.
  ENDIF.
  IF p_allv = abap_true.
    cv_part = `_alle`.
    RETURN.
  ENDIF.
  IF p_var IS INITIAL.
    RETURN.
  ENDIF.

* Ein Variantenname darf Schraegstriche tragen - /SDF/B2S_SFIN etwa -
* und die trennen im Dateisystem Verzeichnisse.
  lv_name = to_lower( CONV string( p_var ) ).
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

* Im Hintergrund und bei SUBMIT laeuft kein PBO, das den Vorschlag
* gefuellt haette.
  DATA lv_part TYPE string.

  cv_base = p_fname.
  CONDENSE cv_base.
  IF cv_base IS INITIAL.
    PERFORM fname_object CHANGING lv_part.
    cv_base = |documizer_atc_{ sy-sysid }{ lv_part }_{ sy-datum }_{ sy-uzeit }|.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& START-OF-SELECTION
*&---------------------------------------------------------------------*
START-OF-SELECTION.

* Das Dokument spricht die Ausgabesprache, seine eigenen Ueberschriften
* eingeschlossen.
  lcl_t=>set_lang( p_langu ).

  DATA(lo_collector) = NEW lcl_collector_atc( iv_mode  = p_mode
                                              iv_var   = p_var
                                              iv_vusr  = p_vusr
                                              iv_allv  = p_allv
                                              iv_hide  = p_hide
                                              iv_langu = p_langu
                                              iv_msg   = p_msg
                                              iv_prio  = p_prio
                                              iv_pcom  = p_pcom
                                              iv_exmp  = p_exmp
                                              iv_cat   = p_cat ).

  DATA lo_coll TYPE REF TO lif_docu_collector.
  lo_coll = lo_collector.
  DATA(lo_doc) = lo_coll->collect( ).

  DATA lo_renderer TYPE REF TO lif_docu_renderer.
  lo_renderer = NEW lcl_renderer_xml( ).

  DATA lv_xml TYPE string.
  IF p_xml = abap_true OR p_rtest = abap_true.
    lv_xml = lo_renderer->render( lo_doc ).
  ENDIF.

  WRITE: / lcl_t=>ui( d = `Documizer - ATC-Pruefkonfiguration`
                      e = `Documizer - ATC check configuration` ).
  ULINE.
  IF p_mode = 'K'.
    WRITE: / lcl_t=>ui( d = `Modus                            : Katalog`
                        e = `Mode                             : catalog` ).
  ELSE.
    WRITE: / lcl_t=>ui( d = `Modus                            : Pruefvariante`
                        e = `Mode                             : check variant` ).
    WRITE: / lcl_t=>ui( d = `Varianten dokumentiert           :`
                        e = `Variants documented              :` ), lo_collector->get_stat_variants( ).
  ENDIF.
  WRITE: / lcl_t=>ui( d = `Checks dokumentiert              :`
                      e = `Checks documented                :` ), lo_collector->get_stat_checks( ).
  IF p_msg = abap_true.
    WRITE: / lcl_t=>ui( d = `Meldungen                        :`
                        e = `Messages                         :` ), lo_collector->get_stat_messages( ).
  ENDIF.
  IF p_prio = abap_true.
    WRITE: / lcl_t=>ui( d = `davon kundeneigen priorisiert    :`
                        e = `of these with customer priority  :` ), lo_collector->get_stat_custom( ).
  ENDIF.
  IF lo_collector->get_stat_broken( ) > 0.
    WRITE: / lcl_t=>ui( d = `nicht ladbar                     :`
                        e = `could not be loaded              :` ), lo_collector->get_stat_broken( ).
    WRITE: / lcl_t=>ui( d = `  (Variante nennt Checks, die es hier nicht gibt)`
                        e = `  (the variant names checks that do not exist here)` ).
  ENDIF.
  IF lv_xml IS NOT INITIAL.
    WRITE: / lcl_t=>ui( d = `XML-Zeichen                      :`
                        e = `XML characters                   :` ), strlen( lv_xml ).
  ENDIF.

* Der Roundtrip prueft das Format an echten Daten, nicht an einem
* Beispiel. Geschrieben wird dabei nichts.
  IF p_rtest = abap_true.
    DATA(lo_doc2) = lcl_parser_xml=>parse( lv_xml ).
    DATA(lv_xml2) = lo_renderer->render( lo_doc2 ).
    IF lv_xml = lv_xml2.
      WRITE: / lcl_t=>ui( d = `Roundtrip                        : IDENTISCH - bestanden`
                          e = `Roundtrip                        : IDENTICAL - passed` ).
    ELSE.
      WRITE: / lcl_t=>ui( d = `Roundtrip                        : ABWEICHUNG`
                          e = `Roundtrip                        : DEVIATION` ), strlen( lv_xml2 ).
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
    WRITE: / lcl_t=>ui( d = `HTML-Zeichen                     :`
                        e = `HTML characters                  :` ), strlen( lv_html ).

    IF p_down = abap_true.
      PERFORM download USING lv_html 'html'.
    ENDIF.
    IF p_dsrv = abap_true AND p_srv IS NOT INITIAL.
      PERFORM download_srv USING lv_html 'html'.
    ENDIF.

    IF sy-batch = abap_false.
      cl_abap_browser=>show_html( html_string = lv_html
                                  title       = 'Documizer' ).
    ELSE.
      WRITE: / lcl_t=>ui( d = `HTML-Anzeige im Hintergrund nicht möglich.`
                          e = `HTML display not possible in the background.` ).
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
