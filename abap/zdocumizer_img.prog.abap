REPORT zdocumizer_img.

************************************************************************
* consiness Documizer - IMG / customizing documentation
*
* Reads an IMG structure tree, assigns the IMG activities to the nodes,
* takes over the SAP standard documentation and reads the assigned
* customizing down to the table contents. On request the nodes are
* overlaid with status and memo from an IMG project.
*
* Everything sits in one report so that it runs after a copy/paste into
* SE38 on any system: chapter model, interfaces, XML renderer and parser
* are identical to ZDOCUMIZER_DEV. In the target design they live as
* global classes in ZCONS_DOCUMIZER_CORE; the duplication is the price
* for being transportable through the clipboard.
*
* Standard interfaces used:
*   STREE_HIERARCHY_READ_ALL_SUBS  structure, texts and node references
*   DOCU_GET                       standard documentation, doc class HY
*   CUS_IMGACH                     header record of the IMG activity
*   CUS_IMGACT                     language-dependent title
*   CUS_ACTOBJ                     assigned customizing objects
*
* The node reference sits in HIER_REF with REF_TYPE = 'COBJ';
* REF_OBJECT is the IMG activity.
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
* Selection screen
*----------------------------------------------------------------------*
* The labels deliberately live in the source and not in the text pool.
* Text elements are a separate program part that does not travel along
* when the source is copied into another system - only the technical
* field names would show up there. Filling COMMENT fields in
* INITIALIZATION keeps the report readable without any rework.

* The gv_* fields are created implicitly by SELECTION-SCREEN COMMENT and
* FRAME TITLE and must not be declared with DATA on top of that -
* otherwise the compiler reports a duplicate declaration.

* Der zuletzt selbst gebildete Dateinamensvorschlag. Nur solange im
* Feld genau dieser Wert steht, darf der naechste Bildaufbau ihn
* ersetzen - sonst waere ein selbst gewaehlter Name beim naechsten
* Enter wieder weg.
DATA gv_fauto TYPE char128.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE gv_blk1.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_ttree FOR FIELD p_tree.
    PARAMETERS p_tree TYPE ttree-id.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tsrch FOR FIELD p_srch.
    PARAMETERS p_srch TYPE tnodeimgt-text.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tproj FOR FIELD p_proj.
    PARAMETERS p_proj TYPE cusstat-project_id.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tonly FOR FIELD p_onlypr.
    PARAMETERS p_onlypr AS CHECKBOX.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE gv_blk2.
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
    SELECTION-SCREEN COMMENT 1(30) gv_tdep FOR FIELD p_depth.
    PARAMETERS p_depth TYPE i DEFAULT 0.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tmaxn FOR FIELD p_maxnod.
    PARAMETERS p_maxnod TYPE i DEFAULT 300.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tsubs FOR FIELD p_subs.
    PARAMETERS p_subs AS CHECKBOX DEFAULT 'X'.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tdoku FOR FIELD p_doku.
    PARAMETERS p_doku AS CHECKBOX DEFAULT 'X'.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tobj FOR FIELD p_obj.
    PARAMETERS p_obj AS CHECKBOX DEFAULT 'X'.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tdata FOR FIELD p_data.
    PARAMETERS p_data AS CHECKBOX DEFAULT 'X'.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tcust FOR FIELD p_cust.
    PARAMETERS p_cust AS CHECKBOX DEFAULT 'X'.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tmaxr FOR FIELD p_maxrow.
    PARAMETERS p_maxrow TYPE i DEFAULT 500.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_thist FOR FIELD p_hist.
    PARAMETERS p_hist AS CHECKBOX.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tcall FOR FIELD p_calls.
    PARAMETERS p_calls AS CHECKBOX.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tnsap FOR FIELD p_nosap.
    PARAMETERS p_nosap AS CHECKBOX.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK b2.

SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE gv_blk3.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tpst FOR FIELD p_pstat.
    PARAMETERS p_pstat AS CHECKBOX DEFAULT 'X'.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tpmem FOR FIELD p_pmemo.
    PARAMETERS p_pmemo AS CHECKBOX DEFAULT 'X'.
  SELECTION-SCREEN END OF LINE.
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
* Startknoten und Zeitstempel; wer ihn ueberschreibt, behaelt seinen
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

* Der zweite Betriebsmodus des Reports: ein vorhandenes Dokument
* einlesen und daraus ein BC-Set anlegen. Geschrieben wird damit noch
* nichts - das Customizing entsteht erst, wenn jemand das Set in
* SCPR20 aktiviert.
SELECTION-SCREEN BEGIN OF BLOCK b4 WITH FRAME TITLE gv_blk4.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tbcs FOR FIELD p_bcs.
    PARAMETERS p_bcs AS CHECKBOX USER-COMMAND bmode.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tbfil FOR FIELD p_bfile.
    PARAMETERS p_bfile TYPE char128 LOWER CASE VISIBLE LENGTH 40.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tbsrv FOR FIELD p_bsrv.
    PARAMETERS p_bsrv AS CHECKBOX.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tbid FOR FIELD p_bid.
    PARAMETERS p_bid TYPE scpr_id.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tbtxt FOR FIELD p_btext.
    PARAMETERS p_btext TYPE scprtext-text.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tbpak FOR FIELD p_bpack.
    PARAMETERS p_bpack TYPE devclass DEFAULT '$TMP'.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tbtr FOR FIELD p_btr.
    PARAMETERS p_btr TYPE trkorr.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tbtst FOR FIELD p_btest.
    PARAMETERS p_btest AS CHECKBOX DEFAULT 'X'.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tbreq FOR FIELD p_breq.
    PARAMETERS p_breq AS CHECKBOX DEFAULT 'X'.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tbrf FOR FIELD p_brfil.
    PARAMETERS p_brfil TYPE char128 LOWER CASE VISIBLE LENGTH 40.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK b4.

INITIALIZATION.
* Screen labels live in the source, not in the text pool, so that a copied
* report is readable in any system. English is the default; German is used
* only when the user is logged on in German.
  IF sy-langu = 'D'.
    gv_blk1  = 'Auswahl der Struktur'.
    gv_blk2  = 'Umfang'.
    gv_blk3  = 'Ausgabe'.
    gv_ttree = 'Struktur-ID (GUID)'.
    gv_tsrch = 'oder Suchbegriff Wurzel'.
    gv_tproj = 'Projekt (Status/Memo)'.
    gv_tonly = 'nur Projektknoten'.
    gv_tlang = 'Ausgabesprache'.
    gv_tfalb = 'Ersatzsprache verwenden'.
    gv_tflng = 'Ersatzsprache'.
    gv_tdep  = 'Max. Tiefe (0 = alle)'.
    gv_tmaxn = 'Max. Kapitel (0 = alle)'.
    gv_tsubs = 'Unterstrukturen auflösen'.
    gv_tdoku = 'Standarddokumentation'.
    gv_tobj  = 'Objektzuordnung'.
    gv_tdata = 'Customizing-Inhalte lesen'.
    gv_tcust = 'nur kundeneigene Einträge'.
    gv_tmaxr = 'Max. Zeilen (0 = alle)'.
    gv_thist = 'Transport-Historie'.
    gv_tcall = 'Ausgehende Aufrufe'.
    gv_tnsap = 'SAP-Standard ausschliessen'.
    gv_tpst  = 'Projektstatus ausgeben'.
    gv_tpmem = 'Projekt-Memo ausgeben'.
    gv_txml  = 'XML erzeugen/ausgeben'.
    gv_thtml = 'HTML erzeugen/anzeigen'.
    gv_tfold = 'HTML einklappen ab Zeilen'.
    gv_trt   = 'Roundtrip prüfen'.
    gv_tdown = 'Download auf PC'.
    gv_tpath = 'Verzeichnis'.
    gv_tfnam = 'Dateiname (ohne Endung)'.
    gv_tdsrv = 'Ablage Appl.-Server'.
    gv_tsrv  = 'Verzeichnis'.
    gv_blk4  = 'BC-Set aus Dokument erzeugen'.
    gv_tbcs  = 'BC-Set erzeugen'.
    gv_tbfil = 'XML-Datei'.
    gv_tbsrv = 'Datei liegt auf Appl.-Server'.
    gv_tbid  = 'Name des BC-Sets'.
    gv_tbtxt = 'Beschreibung'.
    gv_tbpak = 'Paket'.
    gv_tbtr  = 'Auftrag'.
    gv_tbtst = 'Testlauf (nichts anlegen)'.
    gv_tbreq = 'Fehlliste erzeugen'.
    gv_tbrf  = 'Fehlliste - Datei'.
  ELSE.
    gv_blk1  = 'Structure selection'.
    gv_blk2  = 'Scope'.
    gv_blk3  = 'Output'.
    gv_ttree = 'Structure ID (GUID)'.
    gv_tsrch = 'or search term for root'.
    gv_tproj = 'Project (status/memo)'.
    gv_tonly = 'Project nodes only'.
    gv_tlang = 'Output language'.
    gv_tfalb = 'Use fallback language'.
    gv_tflng = 'Fallback'.
    gv_tdep  = 'Max. depth (0 = all)'.
    gv_tmaxn = 'Max. chapters (0 = all)'.
    gv_tsubs = 'Resolve substructures'.
    gv_tdoku = 'Standard documentation'.
    gv_tobj  = 'Object assignment'.
    gv_tdata = 'Read customizing data'.
    gv_tcust = 'Customer entries only'.
    gv_tmaxr = 'Max. rows (0 = all)'.
    gv_thist = 'Transport history'.
    gv_tcall = 'Outgoing references'.
    gv_tnsap = 'Exclude SAP standard'.
    gv_tpst  = 'Show project status'.
    gv_tpmem = 'Show project memo'.
    gv_txml  = 'Create/show XML'.
    gv_thtml = 'Create/show HTML'.
    gv_tfold = 'Collapse HTML from lines'.
    gv_trt   = 'Check roundtrip'.
    gv_tdown = 'Download to PC'.
    gv_tpath = 'Directory'.
    gv_tfnam = 'File name (no extension)'.
    gv_tdsrv = 'Store on app server'.
    gv_tsrv  = 'Directory'.
    gv_blk4  = 'Create BC set from document'.
    gv_tbcs  = 'Create BC set'.
    gv_tbfil = 'XML file'.
    gv_tbsrv = 'File is on the app server'.
    gv_tbid  = 'Name of the BC set'.
    gv_tbtxt = 'Description'.
    gv_tbpak = 'Package'.
    gv_tbtr  = 'Request'.
    gv_tbtst = 'Test run (create nothing)'.
    gv_tbreq = 'Create request list'.
    gv_tbrf  = 'Request list - file'.
  ENDIF.

AT SELECTION-SCREEN OUTPUT.
  PERFORM suggest_fname.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_path.
  PERFORM f4_verzeichnis.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_proj.
  PERFORM f4_projekt.

* Value help for the structure ID. The DDIC search help on TTREE-ID
* returns bare GUIDs without any description and is therefore useless.
* Here the root nodes are offered with their text instead, optionally
* filtered by the search term in the second field.
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_tree.
  PERFORM f4_struktur.

*----------------------------------------------------------------------*
* lcl_cust - resolving and reading the customizing (step 4)
*
* Views and view clusters are always resolved to their base tables. A
* maintenance view cannot be read with SELECT, a database view can - the
* distinction disappears once everything is read from the transparent
* tables.
*
* "Customer entry" is determined by two methods at the same time:
*   namespace   first key field starts with Y, Z or /
*   transport   key shows up in E071K for this table
* Both apply with OR. The namespace also finds customizing that was
* never transported, the transport route also finds keys outside the
* customer namespace. Which method matched is noted on the object.
*----------------------------------------------------------------------*
CLASS lcl_cust DEFINITION.
  PUBLIC SECTION.
    METHODS constructor
      IMPORTING iv_custom TYPE abap_bool
                iv_maxrow TYPE i
                iv_hist   TYPE abap_bool.
    METHODS build
      IMPORTING iv_type           TYPE string
                iv_name           TYPE string
                iv_tcode          TYPE string
      RETURNING VALUE(rt_objects) TYPE ty_objects.
  PRIVATE SECTION.
    TYPES: BEGIN OF ty_fld,
             fieldname TYPE dd03l-fieldname,
             rollname  TYPE dd03l-rollname,
             keyflag   TYPE dd03l-keyflag,
             position  TYPE dd03l-position,
             inttype   TYPE dd03l-inttype,
             intlen    TYPE dd03l-intlen,
           END OF ty_fld.
    TYPES ty_flds TYPE STANDARD TABLE OF ty_fld WITH EMPTY KEY.

    DATA mv_custom TYPE abap_bool.
    DATA mv_maxrow TYPE i.
    DATA mv_hist   TYPE abap_bool.

    METHODS resolve
      IMPORTING iv_type         TYPE string
                iv_name         TYPE string
      RETURNING VALUE(rt_names) TYPE string_table.
    METHODS read_ddic
      IMPORTING iv_tab         TYPE string
      RETURNING VALUE(rt_flds) TYPE ty_flds.
    METHODS read_transports
      IMPORTING iv_tab   TYPE string
                it_flds  TYPE ty_flds
      EXPORTING et_trans TYPE ty_transports
                et_keys  TYPE string_table.
    METHODS fill_data
      IMPORTING iv_tab  TYPE string
                it_flds TYPE ty_flds
                it_keys TYPE string_table
                io_obj  TYPE REF TO lcl_object.
ENDCLASS.

CLASS lcl_cust IMPLEMENTATION.

  METHOD constructor.
    mv_custom = iv_custom.
    mv_maxrow = iv_maxrow.
    mv_hist   = iv_hist.
  ENDMETHOD.

  METHOD resolve.

    DATA lv_view TYPE dd25l-viewname.
    DATA lv_vcl  TYPE vclstruc-vclname.

    CASE iv_type.

      WHEN 'T'.
        APPEND iv_name TO rt_names.

      WHEN 'V' OR 'S'.
        lv_view = iv_name.
        SELECT tabname, tabpos FROM dd26s
          WHERE viewname = @lv_view AND as4local = 'A'
          ORDER BY tabpos
          INTO TABLE @DATA(lt_base).
        IF lt_base IS INITIAL.
          SELECT SINGLE roottab FROM dd25l
            WHERE viewname = @lv_view AND as4local = 'A'
            INTO @DATA(lv_root).
          IF sy-subrc = 0 AND lv_root IS NOT INITIAL.
            APPEND CONV string( lv_root ) TO rt_names.
          ENDIF.
        ELSE.
          LOOP AT lt_base INTO DATA(ls_base).
            APPEND CONV string( ls_base-tabname ) TO rt_names.
          ENDLOOP.
        ENDIF.

      WHEN 'C'.
        lv_vcl = iv_name.
        SELECT object, objpos FROM vclstruc
          WHERE vclname = @lv_vcl
          ORDER BY objpos
          INTO TABLE @DATA(lt_v).
        LOOP AT lt_v INTO DATA(ls_v).
          APPEND LINES OF resolve( iv_type = 'V'
                                   iv_name = CONV string( ls_v-object ) ) TO rt_names.
        ENDLOOP.

    ENDCASE.

    SORT rt_names.
    DELETE ADJACENT DUPLICATES FROM rt_names.

  ENDMETHOD.

  METHOD read_ddic.
    DATA lv_tab TYPE dd03l-tabname.
    lv_tab = iv_tab.
    SELECT fieldname, rollname, keyflag, position, inttype, intlen
      FROM dd03l
      WHERE tabname = @lv_tab AND as4local = 'A' AND fieldname NOT LIKE '.%'
      ORDER BY position
      INTO CORRESPONDING FIELDS OF TABLE @rt_flds.
  ENDMETHOD.

  METHOD read_transports.

    DATA lv_tab TYPE e071k-objname.
    DATA lv_off TYPE i.
    DATA lv_len TYPE i.

    CLEAR: et_trans, et_keys.
    lv_tab = iv_tab.

    SELECT k~trkorr AS trkorr, k~tabkey AS tabkey,
           e~as4user AS as4user, e~as4date AS as4date
      FROM e071k AS k
      INNER JOIN e070 AS e ON e~trkorr = k~trkorr
      WHERE k~pgmid = 'R3TR' AND k~object = 'TABU' AND k~objname = @lv_tab
      INTO TABLE @DATA(lt_k)
      UP TO 500 ROWS.

    IF lt_k IS INITIAL.
      RETURN.
    ENDIF.

    " Determine the position of the first business key field in TABKEY
    LOOP AT it_flds INTO DATA(ls_f) WHERE keyflag = 'X'.
      IF ls_f-fieldname = 'MANDT' OR ls_f-fieldname = 'MANDANT'.
        lv_off = ls_f-intlen.
        CONTINUE.
      ENDIF.
      lv_len = ls_f-intlen.
      EXIT.
    ENDLOOP.

    LOOP AT lt_k INTO DATA(ls_k).
      IF lv_len > 0 AND strlen( ls_k-tabkey ) >= lv_off + lv_len.
        DATA(lv_key) = substring( val = CONV string( ls_k-tabkey )
                                  off = lv_off
                                  len = lv_len ).
        CONDENSE lv_key.
        IF lv_key IS NOT INITIAL.
          APPEND lv_key TO et_keys.
        ENDIF.
      ENDIF.
      APPEND VALUE ty_transport( trkorr = ls_k-trkorr
                                 user   = ls_k-as4user
                                 date   = |{ ls_k-as4date DATE = ISO }| ) TO et_trans.
    ENDLOOP.

    SORT et_keys.
    DELETE ADJACENT DUPLICATES FROM et_keys.
    SORT et_trans BY trkorr.
    DELETE ADJACENT DUPLICATES FROM et_trans COMPARING trkorr.

    LOOP AT et_trans ASSIGNING FIELD-SYMBOL(<ls_t>).
      SELECT SINGLE as4text FROM e07t
        WHERE trkorr = @<ls_t>-trkorr AND langu = @sy-langu
        INTO @DATA(lv_txt).
      IF sy-subrc = 0.
        <ls_t>-text = lv_txt.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD fill_data.

    DATA lt_where   TYPE TABLE OF string.
    DATA lr_tab     TYPE REF TO data.
    DATA lv_cnt     TYPE i.
    DATA lv_max     TYPE i.
    DATA lv_kf      TYPE string.
    DATA lv_in      TYPE string.
    DATA lv_tabname TYPE tabname.
    FIELD-SYMBOLS <lt_data> TYPE STANDARD TABLE.
    FIELD-SYMBOLS <ls_data> TYPE any.
    FIELD-SYMBOLS <lv_val>  TYPE any.

    lv_tabname = iv_tab.
    AUTHORITY-CHECK OBJECT 'S_TABU_NAM'
      ID 'ACTVT' FIELD '03'
      ID 'TABLE' FIELD lv_tabname.
    IF sy-subrc <> 0.
      io_obj->set_note( |{ io_obj->get_note( ) } { lcl_t=>t(
        d = `Keine Leseberechtigung (S_TABU_NAM).`
        e = `No read authorization (S_TABU_NAM).` ) }| ).
      io_obj->set_filter( lcl_t=>t( d = 'GESPERRT' e = 'BLOCKED' ) ).
      RETURN.
    ENDIF.

    IF mv_custom = abap_true.

      LOOP AT it_flds INTO DATA(ls_k) WHERE keyflag = 'X'.
        IF ls_k-fieldname = 'MANDT' OR ls_k-fieldname = 'MANDANT'
          OR ls_k-fieldname = 'SPRAS' OR ls_k-fieldname = 'LANGU'.
          CONTINUE.
        ENDIF.
        IF ls_k-inttype = 'C' OR ls_k-inttype = 'N'.
          lv_kf = ls_k-fieldname.
        ENDIF.
        EXIT.
      ENDLOOP.

      IF lv_kf IS INITIAL.
        io_obj->set_filter( lcl_t=>t( d = 'ALLE' e = 'ALL' ) ).
        io_obj->set_note( |{ io_obj->get_note( ) } { lcl_t=>t(
          d = `Kundenfilter nicht anwendbar.`
          e = `Customer filter not applicable.` ) }| ).
      ELSE.
        APPEND |{ lv_kf } LIKE 'Y%' OR { lv_kf } LIKE 'Z%' OR { lv_kf } LIKE '/%'|
               TO lt_where.
        IF it_keys IS NOT INITIAL.
          LOOP AT it_keys INTO DATA(lv_key).
            IF sy-tabix > 300.
              EXIT.
            ENDIF.
            REPLACE ALL OCCURRENCES OF |'| IN lv_key WITH |''|.
            IF lv_in IS INITIAL.
              lv_in = |'{ lv_key }'|.
            ELSE.
              lv_in = |{ lv_in }, '{ lv_key }'|.
            ENDIF.
          ENDLOOP.
          IF lv_in IS NOT INITIAL.
            APPEND |OR { lv_kf } IN ( { lv_in } )| TO lt_where.
            io_obj->set_filter( lcl_t=>t( d = 'NAMENSRAUM+TRANSPORT' e = 'NAMESPACE+TRANSPORT' ) ).
          ELSE.
            io_obj->set_filter( lcl_t=>t( d = 'NAMENSRAUM' e = 'NAMESPACE' ) ).
          ENDIF.
        ELSE.
          io_obj->set_filter( lcl_t=>t( d = 'NAMENSRAUM' e = 'NAMESPACE' ) ).
        ENDIF.
      ENDIF.

    ELSE.
      io_obj->set_filter( lcl_t=>t( d = 'ALLE' e = 'ALL' ) ).
    ENDIF.

    TRY.
        SELECT COUNT(*) FROM (iv_tab) WHERE (lt_where) INTO @lv_cnt.
      CATCH cx_root.
        io_obj->set_note( |{ io_obj->get_note( ) } { lcl_t=>t(
          d = `Tabelle nicht lesbar.`
          e = `Table cannot be read.` ) }| ).
        RETURN.
    ENDTRY.

    io_obj->set_row_count( lv_cnt ).

    lv_max = mv_maxrow.
    CREATE DATA lr_tab TYPE STANDARD TABLE OF (iv_tab).
    ASSIGN lr_tab->* TO <lt_data>.

    TRY.
        IF lv_max > 0.
          SELECT * FROM (iv_tab) INTO TABLE @<lt_data> UP TO @lv_max ROWS
            WHERE (lt_where).
        ELSE.
          SELECT * FROM (iv_tab) INTO TABLE @<lt_data>
            WHERE (lt_where).
        ENDIF.
      CATCH cx_root.
        io_obj->set_note( |{ io_obj->get_note( ) } { lcl_t=>t(
          d = `Daten nicht lesbar.`
          e = `Data cannot be read.` ) }| ).
        RETURN.
    ENDTRY.

    IF lv_max > 0 AND lv_cnt > lv_max.
      io_obj->set_truncated( abap_true ).
    ENDIF.

    LOOP AT <lt_data> ASSIGNING <ls_data>.
      DATA ls_row TYPE ty_row.
      CLEAR ls_row.
      LOOP AT it_flds INTO DATA(ls_fd).
        ASSIGN COMPONENT ls_fd-fieldname OF STRUCTURE <ls_data> TO <lv_val>.
        IF sy-subrc = 0.
          DATA lv_val TYPE string.
          lv_val = <lv_val>.
          APPEND VALUE ty_cell( name = ls_fd-fieldname value = lv_val ) TO ls_row-cells.
        ENDIF.
      ENDLOOP.
      io_obj->add_row( ls_row ).
    ENDLOOP.

  ENDMETHOD.

  METHOD build.

    DATA(lt_names) = resolve( iv_type = iv_type iv_name = iv_name ).

    IF lt_names IS INITIAL.
      DATA(lo_none) = NEW lcl_object( iv_type  = iv_type
                                      iv_name  = iv_name
                                      iv_tcode = iv_tcode ).
      lo_none->set_note( lcl_t=>t( d = 'Kein lesbares Datenobjekt hinterlegt.'
                                   e = 'No readable data object assigned.' ) ).
      lo_none->set_object( iv_objtype = iv_type iv_objname = iv_name ).
      APPEND lo_none TO rt_objects.
      RETURN.
    ENDIF.

    LOOP AT lt_names INTO DATA(lv_tab).

      DATA(lo_obj) = NEW lcl_object( iv_type  = iv_type
                                     iv_name  = lv_tab
                                     iv_tcode = iv_tcode ).

*     Das Pflegeobjekt selbst, nicht nur die aufgeloeste Basistabelle.
*     Wer den Pflegeapparat im Zielsystem nachziehen will, braucht die
*     Sicht - und die stand bisher nur im Hinweistext, der die Sprache
*     wechselt.
      lo_obj->set_object( iv_objtype = iv_type
                          iv_objname = iv_name ).

      IF lv_tab <> iv_name.
        lo_obj->set_note( |{ lcl_t=>t( d = `Basistabelle aus` e = `Base table from` ) } { iv_name }.| ).
      ENDIF.

      DATA(lt_flds) = read_ddic( lv_tab ).
      LOOP AT lt_flds INTO DATA(ls_f).
        lo_obj->add_field( VALUE ty_field(
          name     = ls_f-fieldname
          rollname = ls_f-rollname
          keyflag  = COND #( WHEN ls_f-keyflag = 'X' THEN abap_true ELSE abap_false ) ) ).
      ENDLOOP.

      DATA lt_keys  TYPE string_table.
      DATA lt_trans TYPE ty_transports.
      CLEAR: lt_keys, lt_trans.

      IF mv_custom = abap_true OR mv_hist = abap_true.
        read_transports( EXPORTING iv_tab   = lv_tab
                                   it_flds  = lt_flds
                         IMPORTING et_trans = lt_trans
                                   et_keys  = lt_keys ).
        IF mv_hist = abap_true.
          LOOP AT lt_trans INTO DATA(ls_t).
            lo_obj->add_transport( ls_t ).
          ENDLOOP.
        ENDIF.
      ENDIF.

      fill_data( iv_tab  = lv_tab
                 it_flds = lt_flds
                 it_keys = lt_keys
                 io_obj  = lo_obj ).

      APPEND lo_obj TO rt_objects.

    ENDLOOP.

  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* lcl_collector_img - the actual subject of step 3
*----------------------------------------------------------------------*
CLASS lcl_collector_img DEFINITION.
  PUBLIC SECTION.
    INTERFACES lif_docu_collector.
    METHODS constructor
      IMPORTING iv_tree_id TYPE ttree-id
                iv_langu   TYPE sy-langu
                iv_depth   TYPE i
                iv_maxnod  TYPE i
                iv_subs    TYPE abap_bool
                iv_doku    TYPE abap_bool
                iv_obj     TYPE abap_bool
                iv_proj    TYPE cusstat-project_id OPTIONAL
                iv_onlypr  TYPE abap_bool OPTIONAL
                iv_pstat   TYPE abap_bool DEFAULT abap_true
                iv_pmemo   TYPE abap_bool DEFAULT abap_true
                iv_falb    TYPE abap_bool DEFAULT abap_false
                iv_flang   TYPE sy-langu  DEFAULT 'E'
                iv_calls   TYPE abap_bool DEFAULT abap_false
                iv_nosap   TYPE abap_bool DEFAULT abap_false
                io_cust    TYPE REF TO lcl_cust OPTIONAL.
    METHODS get_stat_nodes      RETURNING VALUE(rv) TYPE i.
    METHODS get_stat_activities RETURNING VALUE(rv) TYPE i.
    METHODS get_stat_docu       RETURNING VALUE(rv) TYPE i.
    METHODS get_stat_objects    RETURNING VALUE(rv) TYPE i.
    METHODS get_stat_project    RETURNING VALUE(rv) TYPE i.
    METHODS get_stat_fallback   RETURNING VALUE(rv) TYPE i.
    METHODS get_stat_calls      RETURNING VALUE(rv) TYPE i.
  PRIVATE SECTION.
    DATA mv_tree_id TYPE ttree-id.
    DATA mv_langu   TYPE sy-langu.
    DATA mv_depth   TYPE i.
    DATA mv_maxnod  TYPE i.
    DATA mv_subs    TYPE abap_bool.
    DATA mv_doku    TYPE abap_bool.
    DATA mv_obj     TYPE abap_bool.
    TYPES: BEGIN OF ty_pmap,
             node_id TYPE cusstat-node_id,
             status  TYPE string,
             done    TYPE string,
             memo    TYPE string,
           END OF ty_pmap.

    DATA mo_cust    TYPE REF TO lcl_cust.
    DATA mv_proj    TYPE cusstat-project_id.
    DATA mv_onlypr  TYPE abap_bool.
    DATA mv_pstat   TYPE abap_bool.
    DATA mv_pmemo   TYPE abap_bool.
    DATA mv_falb    TYPE abap_bool.
    DATA mv_flang   TYPE sy-langu.
    DATA mv_n_falb  TYPE i.
    DATA mt_pmap    TYPE HASHED TABLE OF ty_pmap WITH UNIQUE KEY node_id.
    DATA mv_n_proj  TYPE i.
    DATA mv_n_nodes TYPE i.
    DATA mv_n_total TYPE i.
    DATA mv_n_act   TYPE i.
    DATA mv_n_docu  TYPE i.
    DATA mv_n_obj   TYPE i.
    DATA mv_calls   TYPE abap_bool.
    DATA mv_nosap   TYPE abap_bool.
    DATA mv_n_call  TYPE i.
    METHODS enrich_activity
      IMPORTING io_chapter  TYPE REF TO lcl_chapter
                iv_activity TYPE string.
    METHODS add_calls
      IMPORTING it_tcode   TYPE string_table
                io_chapter TYPE REF TO lcl_chapter.
    METHODS own_names
      IMPORTING it_name       TYPE ty_names
      RETURNING VALUE(rt_own) TYPE ty_names.
    METHODS tcode_program
      IMPORTING iv_tcode       TYPE string
      RETURNING VALUE(rv_prog) TYPE syrepid.
    METHODS scan_program
      IMPORTING iv_prog       TYPE syrepid
      CHANGING  ct_fun        TYPE string_table
                ct_tab        TYPE string_table
                ct_cls        TYPE string_table.
    METHODS read_documentation
      IMPORTING iv_docu_id TYPE string
      EXPORTING ev_text    TYPE string
                ev_lang    TYPE string.
    METHODS read_docu_lang
      IMPORTING iv_docu_id     TYPE string
                iv_langu       TYPE sy-langu
      RETURNING VALUE(rv_text) TYPE string.
    METHODS load_project.
    METHODS prune
      IMPORTING io_chapter     TYPE REF TO lcl_chapter
      RETURNING VALUE(rv_keep) TYPE abap_bool.
ENDCLASS.

CLASS lcl_collector_img IMPLEMENTATION.

  METHOD constructor.
    mv_tree_id = iv_tree_id.
    mv_langu   = iv_langu.
    mv_depth   = iv_depth.
    mv_maxnod  = iv_maxnod.
    mv_subs    = iv_subs.
    mo_cust    = io_cust.
    mv_proj    = iv_proj.
    mv_onlypr  = iv_onlypr.
    mv_pstat   = iv_pstat.
    mv_pmemo   = iv_pmemo.
    mv_falb    = iv_falb.
    mv_flang   = iv_flang.
    mv_doku    = iv_doku.
    mv_obj     = iv_obj.
    mv_calls   = iv_calls.
    mv_nosap   = iv_nosap.
  ENDMETHOD.

  METHOD lif_docu_collector~collect.

    DATA lt_nodes TYPE STANDARD TABLE OF hier_iface.
    DATA lt_texts TYPE STANDARD TABLE OF hier_texts.
    DATA lt_refs  TYPE STANDARD TABLE OF hier_ref.
    DATA ls_msg   TYPE hier_mess.
    DATA lt_stack TYPE ty_chapters.
    DATA lt_count TYPE STANDARD TABLE OF i WITH EMPTY KEY.
    DATA lv_trunc TYPE abap_bool.

    ro_document = NEW lcl_document( ).

    load_project( ).

    " In project mode with "project nodes only" it would be wasteful to walk
    " the whole implementation guide just to keep a handful of nodes in the
    " end. Which structures are affected is known beforehand: exactly those
    " the project nodes sit in. The entry point is therefore derived from
    " the project data instead of from the selection screen.
    DATA lt_trees TYPE STANDARD TABLE OF ttree-id.
    DATA lv_subs  TYPE abap_bool.

    lv_subs = mv_subs.

    IF mv_onlypr = abap_true AND mv_proj IS NOT INITIAL AND mt_pmap IS NOT INITIAL.
      SELECT DISTINCT tree_id FROM tnodeimg
        FOR ALL ENTRIES IN @mt_pmap
        WHERE node_id = @mt_pmap-node_id
        INTO TABLE @lt_trees.

      " Substructures must not be resolved here. Among the project nodes is
      " the project root as well, and its structure is the complete
      " implementation guide - with resolution the run would cover the
      " whole IMG again. Each project node sits directly in its own
      " structure.
      lv_subs = abap_false.
    ENDIF.

    IF lt_trees IS INITIAL.
      APPEND mv_tree_id TO lt_trees.
    ENDIF.

    DATA lt_ref_idx TYPE HASHED TABLE OF hier_ref
                    WITH UNIQUE KEY node_id ref_type.
    DATA lv_level TYPE i.

    LOOP AT lt_trees INTO DATA(lv_tree).

    CLEAR: lt_nodes, lt_texts, lt_refs, lt_ref_idx, lt_stack.

    " Read structure, texts and node references.
    "
    " Important: STREE_HIERARCHY_READ only returns the structure itself. In
    " the IMG the subchapters are REF nodes pointing to structures of their
    " own - a run without resolution therefore ends after the first level
    " and finds not a single activity. STREE_HIERARCHY_READ_ALL_SUBS
    " resolves the references and returns the continuous tree.
    IF lv_subs = abap_true.
      CALL FUNCTION 'STREE_HIERARCHY_READ_ALL_SUBS'
        EXPORTING
          struct_id  = lv_tree
          spras      = mv_langu
          no_dialog  = abap_true
        IMPORTING
          message    = ls_msg
        TABLES
          nodes      = lt_nodes
          texts      = lt_texts
          references = lt_refs.
    ELSE.
      CALL FUNCTION 'STREE_HIERARCHY_READ'
        EXPORTING
          structure_id       = lv_tree
          language           = mv_langu
          read_also_texts    = abap_true
        IMPORTING
          message            = ls_msg
        TABLES
          list_of_nodes      = lt_nodes
          list_of_texts      = lt_texts
          list_of_references = lt_refs.
    ENDIF.

    " Prepare references and texts for direct access.
    LOOP AT lt_refs INTO DATA(ls_ref_line).
      IF ls_ref_line-ref_type = gc_reftype AND ls_ref_line-del_flag IS INITIAL.
        INSERT ls_ref_line INTO TABLE lt_ref_idx.
      ENDIF.
    ENDLOOP.

    SORT lt_texts BY node_id.

    LOOP AT lt_nodes INTO DATA(ls_node).

      lv_level = ls_node-node_level.

      IF mv_depth > 0 AND lv_level > mv_depth.
        CONTINUE.
      ENDIF.

      " Count every node that fell into the scope - including those the
      " limit cuts off. Only then can the document state how complete it
      " actually is.
      mv_n_total = mv_n_total + 1.

      " In project mode with "project nodes only" the chapter limit must not
      " apply during the traversal: the project nodes often sit deep in the
      " tree, and whatever is cut off beforehand can no longer be found by
      " the pruning afterwards.
      IF mv_maxnod > 0 AND mv_n_nodes >= mv_maxnod
         AND NOT ( mv_onlypr = abap_true AND mv_proj IS NOT INITIAL ).
        lv_trunc = abap_true.
        CONTINUE.
      ENDIF.

      " Cut the stack back to the parent level
      WHILE lines( lt_stack ) >= lv_level.
        DELETE lt_stack INDEX lines( lt_stack ).
      ENDWHILE.

      " Carry the chapter number forward
      WHILE lines( lt_count ) > lv_level.
        DELETE lt_count INDEX lines( lt_count ).
      ENDWHILE.
      WHILE lines( lt_count ) < lv_level.
        APPEND 0 TO lt_count.
      ENDWHILE.
      lt_count[ lv_level ] = lt_count[ lv_level ] + 1.

      DATA lv_id TYPE string.
      CLEAR lv_id.
      LOOP AT lt_count INTO DATA(lv_c).
        IF lv_id IS INITIAL.
          lv_id = |{ lv_c }|.
        ELSE.
          lv_id = |{ lv_id }.{ lv_c }|.
        ENDIF.
      ENDLOOP.

      " Title
      DATA lv_title TYPE string.
      CLEAR lv_title.
      READ TABLE lt_texts INTO DATA(ls_text)
           WITH KEY node_id = ls_node-node_id BINARY SEARCH.
      IF sy-subrc = 0.
        lv_title = ls_text-text.
      ENDIF.

      " Look up the node text in the fallback language. A second call of the
      " function module in the fallback language would cost more than the
      " targeted access to the few nodes without a text.
      IF lv_title IS INITIAL AND mv_falb = abap_true AND mv_flang <> mv_langu.
        SELECT SINGLE text FROM tnodeimgt
          WHERE tree_id = @ls_node-tree_id
            AND node_id = @ls_node-node_id
            AND spras   = @mv_flang
          INTO @DATA(lv_ftext).
        IF sy-subrc = 0.
          lv_title = lv_ftext.
        ENDIF.
      ENDIF.

      " Activity or structure node?
      DATA lv_type TYPE string.
      DATA lv_act  TYPE string.
      CLEAR: lv_type, lv_act.
      READ TABLE lt_ref_idx INTO DATA(ls_ref)
           WITH TABLE KEY node_id = ls_node-node_id ref_type = gc_reftype.
      IF sy-subrc = 0 AND ls_ref-ref_object IS NOT INITIAL.
        lv_type = 'ACTIVITY'.
        lv_act  = ls_ref-ref_object.
      ELSE.
        lv_type = 'STRUCTURE'.
      ENDIF.

      DATA(lo_chapter) = NEW lcl_chapter( iv_id    = lv_id
                                          iv_level = lv_level
                                          iv_type  = lv_type
                                          iv_title = lv_title ).

      IF lines( lt_stack ) > 0.
        DATA(lo_parent) = lt_stack[ lines( lt_stack ) ].
        lo_parent->add_child( lo_chapter ).
      ELSE.
        ro_document->add_chapter( lo_chapter ).
      ENDIF.
      APPEND lo_chapter TO lt_stack.

      " Overlay the project data of the node
      READ TABLE mt_pmap INTO DATA(ls_pm)
           WITH TABLE KEY node_id = ls_node-node_id.
      IF sy-subrc = 0.
        " Status and memo can be switched off separately. The project
        " assignment itself stays in place, otherwise "project nodes only"
        " would no longer find anything.
        lo_chapter->set_project( VALUE ty_project(
          project = mv_proj
          status  = COND #( WHEN mv_pstat = abap_true THEN ls_pm-status )
          done    = COND #( WHEN mv_pstat = abap_true THEN ls_pm-done )
          memo    = COND #( WHEN mv_pmemo = abap_true THEN ls_pm-memo ) ) ).
        mv_n_proj = mv_n_proj + 1.
      ENDIF.

      mv_n_nodes = mv_n_nodes + 1.

      IF lv_act IS NOT INITIAL.
        mv_n_act = mv_n_act + 1.
        enrich_activity( io_chapter = lo_chapter iv_activity = lv_act ).
      ENDIF.

    ENDLOOP.

    ENDLOOP. " next structure

    " With "project nodes only" structure chapters are kept as long as a
    " project node still hangs below them - otherwise the tree falls apart.
    IF mv_onlypr = abap_true AND mv_proj IS NOT INITIAL.
      DATA lt_roots TYPE ty_chapters.
      LOOP AT ro_document->get_chapters( ) INTO DATA(lo_root).
        IF prune( lo_root ) = abap_true.
          APPEND lo_root TO lt_roots.
        ENDIF.
      ENDLOOP.
      ro_document->set_chapters( lt_roots ).
    ENDIF.

    ro_document->set_meta( VALUE ty_meta(
      version    = gc_version
      doc_type   = 'IMG'
      system     = sy-sysid
      client     = sy-mandt
      created_by = sy-uname
      created_at = |{ sy-datum DATE = ISO } { sy-uzeit TIME = ISO }|
      language   = mv_langu
      truncated  = lv_trunc
      node_limit = mv_maxnod
      node_total = mv_n_total ) ).

  ENDMETHOD.

  METHOD enrich_activity.

    DATA ls_reference TYPE ty_reference.
    DATA lv_act TYPE cus_imgach-activity.

    lv_act = iv_activity.

    SELECT SINGLE docu_id, tcode
      FROM cus_imgach
      WHERE activity = @lv_act
      INTO @DATA(ls_head).

    ls_reference-activity = iv_activity.
    IF sy-subrc = 0.
      ls_reference-docu_id = ls_head-docu_id.
      ls_reference-tcode   = ls_head-tcode.
    ENDIF.
    io_chapter->set_reference( ls_reference ).

    " Language-dependent title of the activity if the node text is empty
    IF io_chapter->get_title( ) IS INITIAL.
      SELECT SINGLE text FROM cus_imgact
        WHERE spras = @mv_langu AND activity = @lv_act
        INTO @DATA(lv_text).
      IF sy-subrc <> 0 AND mv_falb = abap_true AND mv_flang <> mv_langu.
        SELECT SINGLE text FROM cus_imgact
          WHERE spras = @mv_flang AND activity = @lv_act
          INTO @lv_text.
      ENDIF.
      IF lv_text IS NOT INITIAL.
        io_chapter->set_title( CONV string( lv_text ) ).
      ENDIF.
    ENDIF.

    " SAP standard documentation, doc class HY
    IF mv_doku = abap_true AND ls_reference-docu_id IS NOT INITIAL.
      DATA lv_docu  TYPE string.
      DATA lv_dlang TYPE string.
      read_documentation( EXPORTING iv_docu_id = ls_reference-docu_id
                          IMPORTING ev_text    = lv_docu
                                    ev_lang    = lv_dlang ).
      IF lv_docu IS NOT INITIAL.
        io_chapter->set_documentation( lv_docu ).
        io_chapter->set_doclang( lv_dlang ).
        mv_n_docu = mv_n_docu + 1.
        IF lv_dlang <> mv_langu.
          mv_n_falb = mv_n_falb + 1.
        ENDIF.
      ENDIF.
    ENDIF.

    " Assigned customizing objects - step 3 deliberately without contents
    DATA lt_tcode TYPE string_table.

    IF mv_obj = abap_true OR mv_calls = abap_true.
      DATA lv_actid TYPE cus_actobj-act_id.
      lv_actid = iv_activity.
      SELECT objecttype, objectname, tcode
        FROM cus_actobj
        WHERE act_id = @lv_actid
        INTO TABLE @DATA(lt_obj).
      LOOP AT lt_obj INTO DATA(ls_obj).
        IF ls_obj-tcode IS NOT INITIAL.
          APPEND CONV string( ls_obj-tcode ) TO lt_tcode.
        ENDIF.
        IF mv_obj = abap_false.
          CONTINUE.
        ENDIF.
        IF mo_cust IS BOUND.
          " Step 4: resolve the object and read its contents
          LOOP AT mo_cust->build( iv_type  = CONV string( ls_obj-objecttype )
                                  iv_name  = CONV string( ls_obj-objectname )
                                  iv_tcode = CONV string( ls_obj-tcode ) ) INTO DATA(lo_built).
            io_chapter->add_object( lo_built ).
            mv_n_obj = mv_n_obj + 1.
          ENDLOOP.
        ELSE.
          io_chapter->add_object( NEW lcl_object(
            iv_type  = CONV string( ls_obj-objecttype )
            iv_name  = CONV string( ls_obj-objectname )
            iv_tcode = CONV string( ls_obj-tcode ) ) ).
          mv_n_obj = mv_n_obj + 1.
        ENDIF.
      ENDLOOP.
    ENDIF.

*   Only the transactions of the assigned objects, never the one on the
*   activity header. That one is a parameter transaction into the IMG
*   framework (SAPLS_CUS_IMG_ACTIVITY) for most activities, and it would
*   drag the whole framework - BM_*, CTO_*, DDIF_* - into every chapter.
    IF mv_calls = abap_true.
      SORT lt_tcode.
      DELETE ADJACENT DUPLICATES FROM lt_tcode.
      IF lt_tcode IS NOT INITIAL.
        add_calls( it_tcode = lt_tcode io_chapter = io_chapter ).
      ENDIF.
    ENDIF.

  ENDMETHOD.

  METHOD own_names.
*   Which of these objects are this system's own development. The criterion
*   is the delivery unit of the package: HOME and LOCAL were built here,
*   everything else was shipped. That is the line SAP itself draws, and
*   unlike a name check it also catches customer objects in a reserved
*   namespace and SAP objects that start with a Z.
    IF it_name IS INITIAL.
      RETURN.
    ENDIF.

    SELECT obj_name, devclass FROM tadir
      FOR ALL ENTRIES IN @it_name
      WHERE pgmid = 'R3TR' AND obj_name = @it_name-table_line
      INTO TABLE @DATA(lt_t).
    IF lt_t IS INITIAL.
      RETURN.
    ENDIF.

    DATA lt_dev TYPE STANDARD TABLE OF devclass.
    LOOP AT lt_t INTO DATA(ls_t).
      APPEND ls_t-devclass TO lt_dev.
    ENDLOOP.
    SORT lt_dev BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_dev COMPARING table_line.

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

  METHOD tcode_program.
*   Behind an IMG activity sits a transaction, and behind the transaction a
*   program. A parameter transaction has no program of its own; it points
*   to another transaction in TSTCP-PARAM as /*<tcode>, which is followed
*   once - a second hop is not worth the reading.
    DATA lv_tc TYPE tstc-tcode.
    lv_tc = iv_tcode.
    IF lv_tc IS INITIAL.
      RETURN.
    ENDIF.

    SELECT SINGLE pgmna FROM tstc WHERE tcode = @lv_tc INTO @DATA(lv_pgm).
    IF sy-subrc = 0 AND lv_pgm IS NOT INITIAL.
      rv_prog = lv_pgm.
      RETURN.
    ENDIF.

    SELECT SINGLE param FROM tstcp WHERE tcode = @lv_tc INTO @DATA(lv_par).
    IF sy-subrc <> 0 OR lv_par IS INITIAL OR lv_par(2) <> '/*'.
      RETURN.
    ENDIF.

    DATA lv_ref TYPE tstc-tcode.
    lv_ref = lv_par+2.
    IF lv_ref CS ' '.
      SPLIT lv_ref AT space INTO DATA(lv_first) DATA(lv_rest2).
      lv_ref = lv_first.
    ENDIF.
    SELECT SINGLE pgmna FROM tstc WHERE tcode = @lv_ref INTO @lv_pgm.
    IF sy-subrc = 0.
      rv_prog = lv_pgm.
    ENDIF.
  ENDMETHOD.

  METHOD scan_program.
*   Same reading as in the developer report: what a program uses is written
*   in its source, and the source is always there. CROSS is empty on many
*   S/4 systems, and WBCROSSGT knows nothing about a plain SELECT.
    DATA lt_src  TYPE string_table.
    DATA lt_incl TYPE STANDARD TABLE OF progname.
    DATA lt_rep  TYPE string_table.
    DATA lv_up   TYPE string.
    DATA lv_hit  TYPE string.

    IF iv_prog IS INITIAL.
      RETURN.
    ENDIF.

    CALL FUNCTION 'RS_GET_ALL_INCLUDES'
      EXPORTING
        program      = iv_prog
      TABLES
        includetab   = lt_incl
      EXCEPTIONS
        not_existent = 1
        no_program   = 2
        OTHERS       = 3.

    READ REPORT iv_prog INTO lt_rep.
    APPEND LINES OF lt_rep TO lt_src.
    LOOP AT lt_incl INTO DATA(lv_inc).
      CLEAR lt_rep.
      READ REPORT lv_inc INTO lt_rep.
      APPEND LINES OF lt_rep TO lt_src.
    ENDLOOP.

    LOOP AT lt_src INTO DATA(lv_line).

      lv_up = to_upper( lv_line ).
      SHIFT lv_up LEFT DELETING LEADING space.
      IF lv_up IS INITIAL OR lv_up(1) = '*'.
        CONTINUE.
      ENDIF.
      IF lv_up CS '"'.
        SPLIT lv_up AT '"' INTO lv_up DATA(lv_rest).
      ENDIF.

      FIND FIRST OCCURRENCE OF PCRE `CALL\s+FUNCTION\s+'([A-Z0-9_/][^']*)'`
        IN lv_up SUBMATCHES lv_hit.
      IF sy-subrc = 0.
        APPEND lv_hit TO ct_fun.
      ENDIF.

      FIND ALL OCCURRENCES OF PCRE
        `\b(?:FROM|JOIN|UPDATE)\s+([A-Z][A-Z0-9_/]{2,29})\b`
        IN lv_up RESULTS DATA(lt_r1).
      LOOP AT lt_r1 INTO DATA(ls_r1).
        DATA(ls_s1) = ls_r1-submatches[ 1 ].
        APPEND lv_up+ls_s1-offset(ls_s1-length) TO ct_tab.
      ENDLOOP.

      FIND ALL OCCURRENCES OF PCRE
        `^(?:INSERT|MODIFY|DELETE)\s+([A-Z][A-Z0-9_/]{2,29})\s+FROM\b`
        IN lv_up RESULTS DATA(lt_r2).
      LOOP AT lt_r2 INTO DATA(ls_r2).
        DATA(ls_s2) = ls_r2-submatches[ 1 ].
        APPEND lv_up+ls_s2-offset(ls_s2-length) TO ct_tab.
      ENDLOOP.

      FIND ALL OCCURRENCES OF PCRE
        `\b([A-Z/][A-Z0-9_/]{2,29})\s*=>`
        IN lv_up RESULTS DATA(lt_r3).
      LOOP AT lt_r3 INTO DATA(ls_r3).
        DATA(ls_s3) = ls_r3-submatches[ 1 ].
        APPEND lv_up+ls_s3-offset(ls_s3-length) TO ct_cls.
      ENDLOOP.

      FIND ALL OCCURRENCES OF PCRE
        `\b(?:REF\s+TO|NEW)\s+([A-Z/][A-Z0-9_/]{2,29})\b`
        IN lv_up RESULTS DATA(lt_r4).
      LOOP AT lt_r4 INTO DATA(ls_r4).
        DATA(ls_s4) = ls_r4-submatches[ 1 ].
        APPEND lv_up+ls_s4-offset(ls_s4-length) TO ct_cls.
      ENDLOOP.

    ENDLOOP.

  ENDMETHOD.

  METHOD add_calls.
*   The technical side of a Customizing activity: which function modules,
*   tables and classes the program behind its transaction touches. Off by
*   default - it reads the complete source of every activity, and in a
*   functional document the detail is not always wanted.
    DATA lt_fun TYPE string_table.
    DATA lt_tab TYPE string_table.
    DATA lt_cls TYPE string_table.
    DATA lt_pro TYPE STANDARD TABLE OF syrepid.

    LOOP AT it_tcode INTO DATA(lv_tc).
      DATA(lv_prog) = tcode_program( lv_tc ).
      IF lv_prog IS NOT INITIAL.
        APPEND lv_prog TO lt_pro.
      ENDIF.
    ENDLOOP.

    SORT lt_pro.
    DELETE ADJACENT DUPLICATES FROM lt_pro.
    IF lt_pro IS INITIAL.
      RETURN.
    ENDIF.

    LOOP AT lt_pro INTO DATA(lv_p).
      scan_program( EXPORTING iv_prog = lv_p
                    CHANGING  ct_fun  = lt_fun
                              ct_tab  = lt_tab
                              ct_cls  = lt_cls ).
    ENDLOOP.

    SORT lt_fun. DELETE ADJACENT DUPLICATES FROM lt_fun.
    SORT lt_tab. DELETE ADJACENT DUPLICATES FROM lt_tab.
    SORT lt_cls. DELETE ADJACENT DUPLICATES FROM lt_cls.

    DATA(lo_c) = NEW lcl_object( iv_type = 'CALLS'
                                 iv_name = |{ concat_lines_of( table = lt_pro sep = `, ` ) }| ).
    lo_c->set_note( lcl_t=>t( d = 'Verwendete Objekte'
                              e = 'Objects used' ) ).

    DATA lv_any TYPE abap_bool.

*   Every candidate is checked against the catalog. A name assembled at
*   runtime or a work area that looks like a table would otherwise show up.
    IF lt_fun IS NOT INITIAL.
      DATA lt_fn TYPE STANDARD TABLE OF rs38l_fnam.
      LOOP AT lt_fun INTO DATA(lv_f).
        APPEND CONV rs38l_fnam( lv_f ) TO lt_fn.
      ENDLOOP.
      SELECT funcname, pname FROM tfdir
        FOR ALL ENTRIES IN @lt_fn
        WHERE funcname = @lt_fn-table_line
        INTO TABLE @DATA(lt_fok).
      SORT lt_fok BY funcname.

*     A function module has no catalog entry of its own - its function
*     group decides whether it belongs to SAP or to this system.
      IF mv_nosap = abap_true.
        DATA lt_grp TYPE ty_names.
        LOOP AT lt_fok INTO DATA(ls_f2).
          IF strlen( ls_f2-pname ) > 4.
            APPEND CONV sobj_name( ls_f2-pname+4 ) TO lt_grp.
          ENDIF.
        ENDLOOP.
        DATA(lt_gown) = own_names( lt_grp ).
        DATA lt_fkeep LIKE lt_fok.
        LOOP AT lt_fok INTO ls_f2.
          IF strlen( ls_f2-pname ) <= 4.
            CONTINUE.
          ENDIF.
          READ TABLE lt_gown TRANSPORTING NO FIELDS
               WITH KEY table_line = ls_f2-pname+4 BINARY SEARCH.
          IF sy-subrc = 0.
            APPEND ls_f2 TO lt_fkeep.
          ENDIF.
        ENDLOOP.
        lt_fok = lt_fkeep.
      ENDIF.

      LOOP AT lt_fok INTO DATA(ls_fok).
        lo_c->add_field( VALUE ty_field(
          name     = ls_fok-funcname
          rollname = lcl_t=>t( d = 'Funktionsbaustein' e = 'function module' ) ) ).
        lv_any = abap_true.
      ENDLOOP.
    ENDIF.

    IF lt_tab IS NOT INITIAL.
      DATA lt_tn TYPE STANDARD TABLE OF sobj_name.
      LOOP AT lt_tab INTO DATA(lv_tn).
        APPEND CONV sobj_name( lv_tn ) TO lt_tn.
      ENDLOOP.
      SELECT obj_name FROM tadir
        FOR ALL ENTRIES IN @lt_tn
        WHERE pgmid = 'R3TR' AND object IN ( 'TABL', 'VIEW' )
          AND obj_name = @lt_tn-table_line
        INTO TABLE @DATA(lt_tok).
      SORT lt_tok BY obj_name.
      IF mv_nosap = abap_true.
        DATA lt_town TYPE ty_names.
        CLEAR lt_town.
        LOOP AT lt_tok INTO DATA(ls_t2).
          APPEND ls_t2-obj_name TO lt_town.
        ENDLOOP.
        DATA(lt_towned) = own_names( lt_town ).
        DATA lt_tkeep LIKE lt_tok.
        LOOP AT lt_tok INTO ls_t2.
          READ TABLE lt_towned TRANSPORTING NO FIELDS
               WITH KEY table_line = ls_t2-obj_name BINARY SEARCH.
          IF sy-subrc = 0.
            APPEND ls_t2 TO lt_tkeep.
          ENDIF.
        ENDLOOP.
        lt_tok = lt_tkeep.
      ENDIF.
      LOOP AT lt_tok INTO DATA(ls_tok).
        lo_c->add_field( VALUE ty_field(
          name     = ls_tok-obj_name
          rollname = lcl_t=>t( d = 'Tabellenzugriff' e = 'table access' ) ) ).
        lv_any = abap_true.
      ENDLOOP.
    ENDIF.

    IF lt_cls IS NOT INITIAL.
      DATA lt_cn TYPE STANDARD TABLE OF sobj_name.
      LOOP AT lt_cls INTO DATA(lv_cn).
        APPEND CONV sobj_name( lv_cn ) TO lt_cn.
      ENDLOOP.
      SELECT obj_name FROM tadir
        FOR ALL ENTRIES IN @lt_cn
        WHERE pgmid = 'R3TR' AND object IN ( 'CLAS', 'INTF' )
          AND obj_name = @lt_cn-table_line
        INTO TABLE @DATA(lt_cok).
      SORT lt_cok BY obj_name.
      IF mv_nosap = abap_true.
        DATA lt_cown TYPE ty_names.
        CLEAR lt_cown.
        LOOP AT lt_cok INTO DATA(ls_c2).
          APPEND ls_c2-obj_name TO lt_cown.
        ENDLOOP.
        DATA(lt_cowned) = own_names( lt_cown ).
        DATA lt_ckeep LIKE lt_cok.
        LOOP AT lt_cok INTO ls_c2.
          READ TABLE lt_cowned TRANSPORTING NO FIELDS
               WITH KEY table_line = ls_c2-obj_name BINARY SEARCH.
          IF sy-subrc = 0.
            APPEND ls_c2 TO lt_ckeep.
          ENDIF.
        ENDLOOP.
        lt_cok = lt_ckeep.
      ENDIF.
      LOOP AT lt_cok INTO DATA(ls_cok).
        lo_c->add_field( VALUE ty_field(
          name     = ls_cok-obj_name
          rollname = lcl_t=>t( d = 'Klassenverwendung' e = 'class used' ) ) ).
        lv_any = abap_true.
      ENDLOOP.
    ENDIF.

    IF lv_any = abap_false.
      RETURN.
    ENDIF.

    io_chapter->add_object( lo_c ).
    mv_n_call = mv_n_call + 1.

  ENDMETHOD.

  METHOD read_documentation.

    CLEAR: ev_text, ev_lang.

    ev_text = read_docu_lang( iv_docu_id = iv_docu_id iv_langu = mv_langu ).
    IF ev_text IS NOT INITIAL.
      ev_lang = mv_langu.
      RETURN.
    ENDIF.

    " If nothing is maintained in the output language, the fallback language
    " is tried. Which language actually delivered is noted on the chapter -
    " otherwise the document would not show why a section is in English.
    IF mv_falb = abap_true AND mv_flang IS NOT INITIAL AND mv_flang <> mv_langu.
      ev_text = read_docu_lang( iv_docu_id = iv_docu_id iv_langu = mv_flang ).
      IF ev_text IS NOT INITIAL.
        ev_lang = mv_flang.
      ENDIF.
    ENDIF.

  ENDMETHOD.

  METHOD read_docu_lang.

    DATA lt_line TYPE STANDARD TABLE OF tline.
    DATA lv_obj  TYPE dokhl-object.

    lv_obj = iv_docu_id.

    CALL FUNCTION 'DOCU_GET'
      EXPORTING
        id                = gc_docuclas
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

    " The ITF format keys are not evaluated here yet; the lines are only
    " joined together. Converting them to HTML or Markdown belongs to
    " step 6.
    LOOP AT lt_line INTO DATA(ls_line).
      IF rv_text IS INITIAL.
        rv_text = ls_line-tdline.
      ELSE.
        rv_text = |{ rv_text }{ cl_abap_char_utilities=>newline }{ ls_line-tdline }|.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD load_project.

    IF mv_proj IS INITIAL.
      RETURN.
    ENDIF.

    " CUSSTAT links project and IMG node through the status GUID,
    " TSTAHTPR holds the memo below it in five comment fields.
    SELECT node_id, status, done, id FROM cusstat
      WHERE project_id = @mv_proj
      INTO TABLE @DATA(lt_st).

    LOOP AT lt_st INTO DATA(ls_st).

      DATA ls_map TYPE ty_pmap.
      CLEAR ls_map.
      ls_map-node_id = ls_st-node_id.
      ls_map-status  = ls_st-status.
      ls_map-done    = |{ ls_st-done }|.

      SELECT SINGLE comm1, comm2, comm3, comm4, comm5 FROM tstahtpr
        WHERE id = @ls_st-id AND langu = @mv_langu
        INTO @DATA(ls_c).
      IF sy-subrc = 0.
        DATA lt_comm TYPE STANDARD TABLE OF string.
        CLEAR lt_comm.
        APPEND ls_c-comm1 TO lt_comm.
        APPEND ls_c-comm2 TO lt_comm.
        APPEND ls_c-comm3 TO lt_comm.
        APPEND ls_c-comm4 TO lt_comm.
        APPEND ls_c-comm5 TO lt_comm.
        LOOP AT lt_comm INTO DATA(lv_comm).
          CONDENSE lv_comm.
          IF lv_comm IS INITIAL.
            CONTINUE.
          ENDIF.
          IF ls_map-memo IS INITIAL.
            ls_map-memo = lv_comm.
          ELSE.
            ls_map-memo = |{ ls_map-memo } { lv_comm }|.
          ENDIF.
        ENDLOOP.
      ENDIF.

      INSERT ls_map INTO TABLE mt_pmap.

    ENDLOOP.

  ENDMETHOD.

  METHOD prune.

    DATA lt_keep TYPE ty_chapters.

    LOOP AT io_chapter->get_children( ) INTO DATA(lo_child).
      IF prune( lo_child ) = abap_true.
        APPEND lo_child TO lt_keep.
      ENDIF.
    ENDLOOP.

    io_chapter->set_children( lt_keep ).

    IF io_chapter->has_project( ) = abap_true OR lines( lt_keep ) > 0.
      rv_keep = abap_true.
    ELSE.
      rv_keep = abap_false.
    ENDIF.

  ENDMETHOD.

  METHOD get_stat_project.
    rv = mv_n_proj.
  ENDMETHOD.

  METHOD get_stat_fallback.
    rv = mv_n_falb.
  ENDMETHOD.

  METHOD get_stat_calls.
    rv = mv_n_call.
  ENDMETHOD.

  METHOD get_stat_nodes.
    rv = mv_n_nodes.
  ENDMETHOD.
  METHOD get_stat_activities.
    rv = mv_n_act.
  ENDMETHOD.
  METHOD get_stat_docu.
    rv = mv_n_docu.
  ENDMETHOD.
  METHOD get_stat_objects.
    rv = mv_n_obj.
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

*----------------------------------------------------------------------*
* lcl_bcset
*----------------------------------------------------------------------*
* Aus einem IMG-Dokument ein BC-Set erzeugen, statt Customizing-
* Tabellen zu beschreiben.
*
* Der Unterschied ist keine Geschmacksfrage. Ein MODIFY auf eine
* Customizing-Tabelle geht an der Pflegesicht vorbei: keine
* Feldpruefung, keine Fremdschluesselpruefung, keine Ereignisse des
* Pflegedialogs - und vor allem keine Aufzeichnung in einem Auftrag.
* Die Zeilen staenden im Zielsystem und in keinem Transport.
*
* Ein BC-Set dreht das um. Dieser Report legt nur die Vorlage an;
* geschrieben wird spaeter mit SCPR20 - mit Pruefungen, mit Protokoll,
* mit Auftragsaufzeichnung, und als bewusste Entscheidung eines
* Menschen statt als Nebenwirkung eines Importlaufs.
*
* Geschrieben wird ueber SCPR_PRSET_DB_SAVE_ORIG_TABLES. Zwei Saetze
* aus seinem eigenen Quelltext bestimmen den Aufbau hier:
* "Er macht keine Ueberpruefungen, ob die Daten korrekt sind" -
* deshalb stehen die Waechter in dieser Klasse. Und: "Wird eine
* Tabelle nicht uebergeben, so werden die Daten auf der Datenbank
* geloescht" - deshalb gehen alle sieben Tabellen hinein, auch die
* leeren.
*
* Aufgezeichnet wird auf Ebene der Basistabellen, weil der Sammler sie
* liest: OBJECTTYPE 'T', OBJECTNAME gleich Tabellenname. Das ist in
* sich stimmig - SAP legt selbst solche BC-Sets an (NRIVS/SNUMS). Ein
* BC-Set auf Sichtebene waere naeher an SM30, verlangte aber, dass
* schon der Export auf Sichtebene liest.
CLASS lcl_bcset DEFINITION.
  PUBLIC SECTION.
    TYPES: BEGIN OF ty_bclog,
             tab    TYPE string,
             action TYPE string,
             text   TYPE string,
           END OF ty_bclog.
    TYPES ty_bclogs TYPE STANDARD TABLE OF ty_bclog WITH EMPTY KEY.

*   Was im Zielsystem fehlt, ist keine Randnotiz, sondern das
*   Wesentliche: die kundeneigenen Tabellen. Sie werden mitgezaehlt,
*   damit daraus eine Arbeitsliste fuer den Entwickler-Report werden
*   kann.
    TYPES: BEGIN OF ty_miss,
             type     TYPE string,
             name     TYPE string,
             activity TYPE string,
           END OF ty_miss.
    TYPES ty_misses TYPE STANDARD TABLE OF ty_miss WITH EMPTY KEY.

    METHODS constructor
      IMPORTING iv_id   TYPE scpr_id
                iv_text TYPE string
                iv_pack TYPE devclass
                iv_tr   TYPE trkorr
                iv_test TYPE abap_bool.

    METHODS build
      IMPORTING io_document  TYPE REF TO lcl_document
      RETURNING VALUE(rv_ok) TYPE abap_bool.

    METHODS get_log     RETURNING VALUE(rt_log)  TYPE ty_bclogs.
    METHODS get_missing RETURNING VALUE(rt_miss) TYPE ty_misses.
    METHODS get_tables  RETURNING VALUE(rv_n)   TYPE i.
    METHODS get_records RETURNING VALUE(rv_n)   TYPE i.
    METHODS get_values  RETURNING VALUE(rv_n)   TYPE i.
    METHODS get_clidep  RETURNING VALUE(rv_f)   TYPE abap_bool.

  PRIVATE SECTION.
    DATA mv_id     TYPE scpr_id.
    DATA mv_text   TYPE string.
    DATA mv_pack   TYPE devclass.
    DATA mv_tr     TYPE trkorr.
    DATA mv_test   TYPE abap_bool.
    DATA mv_clidep TYPE scprattr-cli_dep.
    DATA mv_ref    TYPE scprattr-refname.
    DATA mv_rec    TYPE i.
    DATA mt_vals   TYPE STANDARD TABLE OF scprvals WITH EMPTY KEY.
    DATA mt_reca   TYPE STANDARD TABLE OF scprreca WITH EMPTY KEY.
    DATA mt_tabs   TYPE STANDARD TABLE OF tabname WITH EMPTY KEY.
    DATA mt_miss   TYPE ty_misses.
    DATA mt_log    TYPE ty_bclogs.

    METHODS walk
      IMPORTING it_chapters TYPE ty_chapters.
    METHODS add_object
      IMPORTING io_object TYPE REF TO lcl_object
                is_ref    TYPE ty_reference.
    METHODS save
      RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS note
      IMPORTING iv_tab    TYPE clike
                iv_action TYPE string
                iv_text   TYPE string.
    METHODS want
      IMPORTING iv_type TYPE string
                iv_name TYPE string
                is_ref  TYPE ty_reference.
ENDCLASS.

CLASS lcl_bcset IMPLEMENTATION.

  METHOD constructor.
    mv_id   = iv_id.
    mv_text = iv_text.
    mv_pack = iv_pack.
    mv_tr   = iv_tr.
    mv_test = iv_test.
  ENDMETHOD.

  METHOD note.
    APPEND VALUE ty_bclog( tab    = |{ iv_tab }|
                           action = iv_action
                           text   = iv_text ) TO mt_log.
  ENDMETHOD.

  METHOD get_log.
    rt_log = mt_log.
  ENDMETHOD.

  METHOD get_missing.
    rt_miss = mt_miss.
  ENDMETHOD.

  METHOD want.

*   Doppelte Anforderungen bringen dem Entwickler-Report nichts - er
*   entdoppelt zwar selbst, aber eine Liste, die dreimal dasselbe
*   verlangt, liest sich wie ein Fehler.
    IF iv_name IS INITIAL.
      RETURN.
    ENDIF.
    READ TABLE mt_miss TRANSPORTING NO FIELDS
         WITH KEY type = iv_type name = iv_name.
    IF sy-subrc = 0.
      RETURN.
    ENDIF.

*   Angefordert wird nur, was hier wirklich fehlt. Der erste Lauf
*   verlangte SM30 - eine SAP-Standardtransaktion, die in jedem System
*   steht. Eine Fehlliste, die Vorhandenes anfordert, kostet den
*   Entwickler im Quellsystem Zeit und Vertrauen.
    DATA lv_tab  TYPE tabname.
    DATA lv_view TYPE dd25l-viewname.
    DATA lv_vcl  TYPE vcldir-vclname.
    DATA lv_tcod TYPE tstc-tcode.

    CASE iv_type.

      WHEN 'TABL'.
        lv_tab = iv_name.
        SELECT SINGLE @abap_true FROM dd02l
          WHERE tabname = @lv_tab AND as4local = 'A'
          INTO @DATA(lv_e1).
        IF lv_e1 = abap_true.
          RETURN.
        ENDIF.

      WHEN 'VIEW'.
        lv_view = iv_name.
        SELECT SINGLE @abap_true FROM dd25l
          WHERE viewname = @lv_view AND as4local = 'A'
          INTO @DATA(lv_e2).
        IF lv_e2 = abap_true.
          RETURN.
        ENDIF.

      WHEN 'VCLS'.
        lv_vcl = iv_name.
        SELECT SINGLE @abap_true FROM vcldir
          WHERE vclname = @lv_vcl
          INTO @DATA(lv_e3).
        IF lv_e3 = abap_true.
          RETURN.
        ENDIF.

      WHEN 'TRAN'.
        lv_tcod = iv_name.
        SELECT SINGLE @abap_true FROM tstc
          WHERE tcode = @lv_tcod
          INTO @DATA(lv_e4).
        IF lv_e4 = abap_true.
          RETURN.
        ENDIF.

    ENDCASE.

    APPEND VALUE ty_miss( type     = iv_type
                          name     = iv_name
                          activity = is_ref-activity ) TO mt_miss.

  ENDMETHOD.

  METHOD get_tables.
    rv_n = lines( mt_tabs ).
  ENDMETHOD.

  METHOD get_records.
    rv_n = lines( mt_reca ).
  ENDMETHOD.

  METHOD get_values.
    rv_n = lines( mt_vals ).
  ENDMETHOD.

  METHOD get_clidep.
    rv_f = mv_clidep.
  ENDMETHOD.

  METHOD build.

*   Anlegen darf nur, wer darf. Die Pruefung steht vor der ersten
*   Zeile Arbeit, nicht dahinter.
    CALL FUNCTION 'SCPR_AUTHORITY_CHECK'
      EXPORTING  task             = 'CREATE'
      EXCEPTIONS wrong_parameters = 1
                 no_authority     = 2
                 OTHERS           = 3.
    IF sy-subrc <> 0.
      note( iv_tab    = mv_id
            iv_action = lcl_t=>ui( d = `Abbruch` e = `aborted` )
            iv_text   = lcl_t=>ui( d = `Keine Berechtigung fuer BC-Sets (S_BCSETS).`
                                   e = `No authorization for BC sets (S_BCSETS).` ) ).
      RETURN.
    ENDIF.

    walk( io_document->get_chapters( ) ).

    IF mt_reca IS INITIAL.
      note( iv_tab    = mv_id
            iv_action = lcl_t=>ui( d = `nichts zu tun` e = `nothing to do` )
            iv_text   = lcl_t=>ui( d = `Kein uebernehmbarer Datensatz im Dokument.`
                                   e = `No usable record in the document.` ) ).
      RETURN.
    ENDIF.

    IF mv_test = abap_true.
      rv_ok = abap_true.
      RETURN.
    ENDIF.

    rv_ok = save( ).

  ENDMETHOD.

  METHOD walk.

    LOOP AT it_chapters INTO DATA(lo_chapter).
      DATA(ls_ref) = lo_chapter->get_reference( ).
      LOOP AT lo_chapter->get_objects( ) INTO DATA(lo_object).
        add_object( io_object = lo_object is_ref = ls_ref ).
      ENDLOOP.
      walk( lo_chapter->get_children( ) ).
    ENDLOOP.

  ENDMETHOD.

  METHOD add_object.

    DATA lv_tab TYPE tabname.
    DATA lv_val TYPE scprvals-value.

    DATA(lt_rows) = io_object->get_rows( ).
    IF lt_rows IS INITIAL.
      RETURN.
    ENDIF.

    lv_tab = to_upper( io_object->get_name( ) ).

*   Ein abgeschnittenes Objekt ist gefaehrlicher als ein fehlendes:
*   das BC-Set saehe vollstaendig aus und waere es nicht. Genau diese
*   Sorte Fehler faellt erst im Zielsystem auf, und dann als
*   fehlendes Customizing.
    IF io_object->get_truncated( ) = abap_true.
      note( iv_tab    = lv_tab
            iv_action = lcl_t=>ui( d = `uebersprungen` e = `skipped` )
            iv_text   = lcl_t=>ui( d = `Daten im Export abgeschnitten - Zeilengrenze erhoehen.`
                                   e = `Data truncated during export - raise the row limit.` ) ).
      RETURN.
    ENDIF.

    SELECT SINGLE contflag FROM dd02l
      WHERE tabname = @lv_tab AND as4local = 'A'
      INTO @DATA(lv_cont).
    IF sy-subrc <> 0.
      note( iv_tab    = lv_tab
            iv_action = lcl_t=>ui( d = `uebersprungen` e = `skipped` )
            iv_text   = lcl_t=>ui( d = `Nicht im Data Dictionary.`
                                   e = `Not in the Data Dictionary.` ) ).
*     Genau hier faellt das kundeneigene Customizing durch, und genau
*     das ist das Interessante. Der Name wandert in die Fehlliste,
*     damit der Entwickler-Report im Quellsystem die Tabelle nachliefern
*     kann. Die Aktivitaet kommt mit, damit hinterher nachvollziehbar
*     ist, woher die Anforderung stammt.
      want( iv_type = 'TABL' iv_name = CONV string( lv_tab )
            is_ref = is_ref ).

*     Mit der Basistabelle allein laesst sich das Customizing
*     aktivieren, aber nicht pflegen. Dazu gehoeren die Pflegesicht und
*     die Transaktion; den Pflegedialog selbst kann kein Baustein
*     dialogfrei erzeugen - SE54 bleibt Handarbeit.
      DATA(lv_ot) = to_upper( io_object->get_objtype( ) ).
      DATA(lv_on) = to_upper( io_object->get_objname( ) ).
      IF lv_on IS NOT INITIAL AND lv_on <> lv_tab.
        CASE lv_ot.
          WHEN 'V' OR 'S'.
            want( iv_type = 'VIEW' iv_name = lv_on is_ref = is_ref ).
          WHEN 'C'.
            want( iv_type = 'VCLS' iv_name = lv_on is_ref = is_ref ).
        ENDCASE.
      ENDIF.

      DATA(lv_tc) = to_upper( io_object->get_tcode( ) ).
      IF lv_tc IS NOT INITIAL.
        want( iv_type = 'TRAN' iv_name = lv_tc is_ref = is_ref ).
      ENDIF.

      RETURN.
    ENDIF.

*   Nur Customizing. Eine Lieferklasse A traegt Bewegungsdaten, und
*   die haben in einem BC-Set nichts verloren.
    IF lv_cont <> 'C' AND lv_cont <> 'G' AND lv_cont <> 'E'.
      note( iv_tab    = lv_tab
            iv_action = lcl_t=>ui( d = `uebersprungen` e = `skipped` )
            iv_text   = |{ lcl_t=>ui( d = `Lieferklasse` e = `Delivery class` ) } { lv_cont } - | &&
                        lcl_t=>ui( d = `kein Customizing.` e = `not customizing.` ) ).
      RETURN.
    ENDIF.

*   Das Mandantenfeld reist als Schluessel ohne Wert mit. Den Mandanten
*   setzt die Aktivierung im Zielsystem - er gehoert dem Zielsystem,
*   nicht dem Dokument. SAP haelt es in seinen eigenen BC-Sets genauso.
    SELECT SINGLE fieldname FROM dd03l
      WHERE tabname = @lv_tab AND as4local = 'A' AND datatype = 'CLNT'
      INTO @DATA(lv_clnt).
    IF sy-subrc = 0.
      mv_clidep = 'X'.
    ELSE.
      CLEAR lv_clnt.
    ENDIF.

*   Dieselbe Tabelle haengt oft an mehreren IMG-Aktivitaeten - T000 kam
*   im ersten echten Dokument viermal vor, TVAK zweimal. Der Sammler
*   liest sie jedes Mal vollstaendig und mit demselben Filter, es sind
*   also dieselben Zeilen. Ein zweites Mal aufgenommen waeren sie
*   Dubletten unter neuen Satznummern, und das BC-Set schriebe
*   denselben Satz mehrfach.
*
*   Registriert wird erst hier, hinter den Waechtern: eine wegen
*   Abschneidung uebersprungene Tabelle darf ein spaeteres,
*   vollstaendiges Vorkommen nicht blockieren.
    READ TABLE mt_tabs TRANSPORTING NO FIELDS WITH KEY table_line = lv_tab.
    IF sy-subrc = 0.
      note( iv_tab    = lv_tab
            iv_action = lcl_t=>ui( d = `uebersprungen` e = `skipped` )
            iv_text   = lcl_t=>ui( d = `Bereits aus einer anderen Aktivitaet aufgenommen.`
                                   e = `Already included from another activity.` ) ).
      RETURN.
    ENDIF.
    APPEND lv_tab TO mt_tabs.

    IF mv_ref IS INITIAL AND is_ref-activity IS NOT INITIAL.
      mv_ref = is_ref-activity.
    ENDIF.

    DATA(lt_flds) = io_object->get_fields( ).
    DATA lv_taken TYPE i.
    DATA lv_long  TYPE i.

    LOOP AT lt_rows INTO DATA(ls_row).

      DATA lt_tmp TYPE STANDARD TABLE OF scprvals WITH EMPTY KEY.
      DATA lv_skip TYPE abap_bool.
      CLEAR: lt_tmp, lv_skip.

      LOOP AT ls_row-cells INTO DATA(ls_cell).

        DATA ls_val TYPE scprvals.
        CLEAR ls_val.
        ls_val-id        = mv_id.
        ls_val-version   = 'N'.
        ls_val-tablename = lv_tab.
        ls_val-fieldname = to_upper( ls_cell-name ).

        READ TABLE lt_flds INTO DATA(ls_fld)
             WITH KEY name = ls_cell-name.
        IF sy-subrc = 0 AND ls_fld-keyflag = abap_true.
          ls_val-flag = 'KEY'.
        ELSE.
          ls_val-flag = 'USE'.
        ENDIF.

        IF lv_clnt IS NOT INITIAL AND ls_val-fieldname = lv_clnt.
          ls_val-flag = 'KEY'.
          CLEAR ls_val-value.
        ELSE.
*         Stillschweigend abschneiden waere derselbe Fehler wie eine
*         abgeschnittene Tabelle - nur eine Ebene tiefer. Der ganze
*         Satz faellt weg, und es steht im Protokoll.
          IF strlen( ls_cell-value ) > 255.
            lv_skip = abap_true.
            EXIT.
          ENDIF.
          lv_val = ls_cell-value.
          ls_val-value = lv_val.
        ENDIF.

        APPEND ls_val TO lt_tmp.
      ENDLOOP.

      IF lv_skip = abap_true OR lt_tmp IS INITIAL.
        lv_long = lv_long + 1.
        CONTINUE.
      ENDIF.

      mv_rec = mv_rec + 1.
      DATA lv_recnr TYPE scprvals-recnumber.
      lv_recnr = |{ mv_rec }|.

      LOOP AT lt_tmp INTO ls_val.
        ls_val-recnumber = lv_recnr.
        APPEND ls_val TO mt_vals.
      ENDLOOP.

      APPEND VALUE scprreca( id         = mv_id
                             version    = 'N'
                             tablename  = lv_tab
                             recnumber  = lv_recnr
                             objectname = lv_tab
                             objecttype = 'T'
                             activity   = is_ref-activity ) TO mt_reca.
      lv_taken = lv_taken + 1.
    ENDLOOP.

    note( iv_tab    = lv_tab
          iv_action = lcl_t=>ui( d = `aufgenommen` e = `included` )
          iv_text   = |{ lv_taken } { lcl_t=>ui( d = `Saetze` e = `records` ) }| &&
                      COND #( WHEN lv_long > 0
                              THEN |, { lv_long } { lcl_t=>ui(
                                     d = `wegen Feldlaenge ueber 255 ausgelassen`
                                     e = `omitted, field longer than 255` ) }|
                              ELSE `` ) ).

  ENDMETHOD.

  METHOD save.

    DATA lt_vall  TYPE STANDARD TABLE OF scprvall WITH EMPTY KEY.
    DATA lt_skeys TYPE STANDARD TABLE OF scprskeys WITH EMPTY KEY.
    DATA lt_fldv  TYPE STANDARD TABLE OF scprfldv WITH EMPTY KEY.
    DATA lt_pprl  TYPE STANDARD TABLE OF scprpprl WITH EMPTY KEY.
    DATA lt_text  TYPE STANDARD TABLE OF scprtext WITH EMPTY KEY.
    DATA lv_comp  TYPE dlvunit.
    DATA lv_rel   TYPE saprelease.
    DATA lv_txt   TYPE scprtext-text.

    lv_txt = mv_text.
    APPEND VALUE scprtext( langu   = sy-langu
                           id      = mv_id
                           version = 'N'
                           text    = lv_txt ) TO lt_text.

    CALL FUNCTION 'SCPR_SV_DEVCLASS_GET'
      EXPORTING devclass  = mv_pack
      IMPORTING component = lv_comp
                release   = lv_rel.

*   SCPRSKEYS bleibt leer: SCPR_TEMPL_DB_SCPRSKEYS_CALC steigt bei
*   einer anderen Kategorie als Switch sofort wieder aus. Fuer ein
*   klassisches BC-Set gibt es dort nichts zu rechnen.
    CALL FUNCTION 'SCPR_PRSET_DB_SAVE_ORIG_TABLES'
      EXPORTING  profid                      = mv_id
                 version                     = 'N'
                 proftype                    = 'TMV'
                 category                    = ' '
                 cli_dep                     = mv_clidep
                 cli_cas                     = ' '
                 reftype                     = 'SIMG'
                 refname                     = mv_ref
                 orgid                       = '/CUSTOMER/'
                 component                   = lv_comp
                 minrelease                  = lv_rel
                 maxrelease                  = '*'
                 profstate                   = ' '
                 act_info                    = ' '
                 langu                       = sy-langu
                 proftext                    = lv_txt
      TABLES     scprvals                    = mt_vals
                 scprvall                    = lt_vall
                 scprreca                    = mt_reca
                 scprskeys                   = lt_skeys
                 scprfldv                    = lt_fldv
                 scprtext                    = lt_text
                 scprpprl                    = lt_pprl
      EXCEPTIONS no_profile_id               = 1
                 wrong_version               = 2
                 wrong_proftype              = 3
                 wrong_category              = 4
                 no_profile_text             = 5
                 error_in_writing_attr       = 6
                 error_in_writing_text       = 7
                 error_in_deleting_text      = 8
                 error_in_writing_data       = 9
                 error_in_deleting_data      = 10
                 error_in_writing_vals       = 11
                 error_in_deleting_vals      = 12
                 error_in_writing_fldtxtvar  = 13
                 error_in_deleting_fldtxtvar = 14
                 OTHERS                      = 15.
    IF sy-subrc <> 0.
      DATA(lv_rc1) = sy-subrc.
      note( iv_tab    = mv_id
            iv_action = lcl_t=>ui( d = `Fehler` e = `error` )
            iv_text   = |SCPR_PRSET_DB_SAVE_ORIG_TABLES subrc { lv_rc1 }| ).
      RETURN.
    ENDIF.

*   Ohne Katalogeintrag ist das BC-Set nicht auslieferbar. Die
*   Parameter sind gegen die Felder von TADIR typisiert - ein nur
*   konvertierbares Feld reicht dort nicht.
    DATA lv_obj  TYPE tadir-object.
    DATA lv_name TYPE tadir-obj_name.
    DATA lv_corr TYPE tadir-korrnum.
    DATA lv_srcs TYPE tadir-srcsystem.
    DATA lv_auth TYPE tadir-author.
    DATA lv_lang TYPE tadir-masterlang.

    lv_obj  = 'SCP1'.
    lv_name = mv_id.
    lv_srcs = sy-sysid.
    lv_auth = sy-uname.
    lv_lang = sy-langu.
    IF mv_pack NP '$*'.
      lv_corr = mv_tr.
    ENDIF.

    CALL FUNCTION 'TR_TADIR_INTERFACE'
      EXPORTING  wi_test_modus       = abap_false
                 wi_tadir_pgmid      = 'R3TR'
                 wi_tadir_object     = lv_obj
                 wi_tadir_obj_name   = lv_name
                 wi_tadir_devclass   = mv_pack
                 wi_tadir_masterlang = lv_lang
                 wi_tadir_author     = lv_auth
                 wi_tadir_srcsystem  = lv_srcs
                 wi_tadir_korrnum    = lv_corr
      EXCEPTIONS OTHERS              = 1.
    IF sy-subrc <> 0.
      DATA(lv_rc2) = sy-subrc.
      note( iv_tab    = mv_id
            iv_action = lcl_t=>ui( d = `Warnung` e = `warning` )
            iv_text   = |TR_TADIR_INTERFACE subrc { lv_rc2 }| ).
    ENDIF.

    COMMIT WORK AND WAIT.

*   Nicht dem Baustein glauben, sondern nachsehen. Genau diese Sorte
*   Nachfrage haette anderswo schon einmal viel Zeit gespart.
    SELECT COUNT(*) FROM scprvals
      WHERE id = @mv_id AND version = 'N' INTO @DATA(lv_chk).
    IF lv_chk <> lines( mt_vals ).
      note( iv_tab    = mv_id
            iv_action = lcl_t=>ui( d = `Warnung` e = `warning` )
            iv_text   = |{ lcl_t=>ui( d = `Gesichert` e = `Saved` ) } { lv_chk }, | &&
                        |{ lcl_t=>ui( d = `erwartet` e = `expected` ) } { lines( mt_vals ) }| ).
      RETURN.
    ENDIF.

    rv_ok = abap_true.

  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* lcl_request
*----------------------------------------------------------------------*
* Die Fehlliste: was im Zielsystem fehlt, als Arbeitsauftrag fuer den
* Entwickler-Report im Quellsystem.
*
* Ein eigenes, kleines Format - bewusst weder ein IMG- noch ein
* DEV-Dokument. Die beiden Reports sprechen unterschiedliche
* Vokabulare (<object type= name=> gegen <definition kind=>), und eines
* davon zu verbiegen waere teurer als dreissig Zeilen Schreiber hier
* und dreissig Zeilen Leser drueben.
*
* Der Auftrag traegt nur Typ und Name. Alles Weitere - Datenelemente,
* Domaenen, Reihenfolge beim Anlegen - findet der Entwickler-Report
* selbst; das ist seine Aufgabe und er kann sie laengst.
CLASS lcl_request DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS render
      IMPORTING it_miss       TYPE lcl_bcset=>ty_misses
                iv_source     TYPE string
      RETURNING VALUE(rv_xml) TYPE string.
ENDCLASS.

CLASS lcl_request IMPLEMENTATION.

  METHOD render.

    DATA lo_sw TYPE REF TO cl_sxml_string_writer.
    DATA lo_w  TYPE REF TO if_sxml_writer.

    lo_sw = cl_sxml_string_writer=>create( type = if_sxml=>co_xt_xml10 ).
    lo_w  = lo_sw.
    lo_w->set_option( option = if_sxml_writer=>co_opt_linebreaks ).
    lo_w->set_option( option = if_sxml_writer=>co_opt_indent ).

    lo_w->open_element( name = 'documizer' ).
    lo_w->write_attribute( name = 'version' value = gc_version ).
    lo_w->write_attribute( name = 'type'    value = 'REQUEST' ).

    lo_w->open_element( name = 'meta' ).
    lo_w->open_element( name = 'system' ).
    lo_w->write_value( CONV string( sy-sysid ) ).
    lo_w->close_element( ).
    lo_w->open_element( name = 'client' ).
    lo_w->write_value( CONV string( sy-mandt ) ).
    lo_w->close_element( ).
    lo_w->open_element( name = 'created_by' ).
    lo_w->write_value( CONV string( sy-uname ) ).
    lo_w->close_element( ).
    lo_w->open_element( name = 'created_at' ).
    lo_w->write_value( |{ sy-datum DATE = ISO } { sy-uzeit TIME = ISO }| ).
    lo_w->close_element( ).
*   Woher das Dokument kam, das die Luecke gezeigt hat. Wer den Auftrag
*   spaeter in die Hand nimmt, soll das Quellsystem nicht raten muessen.
    lo_w->open_element( name = 'source' ).
    lo_w->write_value( iv_source ).
    lo_w->close_element( ).
    lo_w->close_element( ).

    lo_w->open_element( name = 'objects' ).
    LOOP AT it_miss INTO DATA(ls_miss).
      lo_w->open_element( name = 'object' ).
      lo_w->write_attribute( name = 'type' value = ls_miss-type ).
      lo_w->write_attribute( name = 'name' value = ls_miss-name ).
      IF ls_miss-activity IS NOT INITIAL.
        lo_w->write_attribute( name = 'activity' value = ls_miss-activity ).
      ENDIF.
      lo_w->close_element( ).
    ENDLOOP.
    lo_w->close_element( ).

    lo_w->close_element( ).

    rv_xml = cl_abap_codepage=>convert_from( lo_sw->get_output( ) ).

  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* BC-Set aus einem Dokument erzeugen
*----------------------------------------------------------------------*
FORM bcset.

  DATA lv_xml  TYPE string.
  DATA lv_x    TYPE xstring.
  DATA lv_file TYPE string.
* GUI_UPLOAD und SCMS_BINARY_TO_XSTRING erwarten beide die Zeilenstruktur
* SOLIX, nicht ein blankes X-Feld. Eine Tabelle elementarer Zeilen endet
* in CALL_FUNCTION_CONFLICT_TAB_TYP.
  DATA lt_bin  TYPE solix_tab.
  DATA lv_len  TYPE i.
  DATA lv_id   TYPE scpr_id.

  WRITE: / lcl_t=>ui( d = `Documizer - BC-Set aus IMG-Dokument`
                      e = `Documizer - BC set from IMG document` ).
  ULINE.

  lv_id = to_upper( p_bid ).
  IF lv_id IS INITIAL.
    WRITE: / lcl_t=>ui( d = `Kein Name fuer das BC-Set angegeben.`
                        e = `No name given for the BC set.` ).
    RETURN.
  ENDIF.
* Ein BC-Set ist ein Repository-Objekt. Der Kundennamensraum gilt hier
* wie ueberall sonst.
  IF lv_id(1) <> 'Z' AND lv_id(1) <> 'Y' AND lv_id(1) <> '/'.
    WRITE: / lcl_t=>ui( d = `Name ausserhalb des Kundennamensraums (Z, Y oder /...).`
                        e = `Name outside the customer namespace (Z, Y or /...).` ).
    RETURN.
  ENDIF.

  lv_file = p_bfile.
  CONDENSE lv_file.
  IF lv_file IS INITIAL.
    WRITE: / lcl_t=>ui( d = `Keine Datei angegeben.` e = `No file given.` ).
    RETURN.
  ENDIF.

  IF p_bsrv = abap_true.
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

  DATA(ls_meta) = lo_doc->get_meta( ).
  WRITE: / lcl_t=>ui( d = `Datei                            :` e = `File                             :` ), lv_file.
  WRITE: / lcl_t=>ui( d = `Quellsystem                      :` e = `Source system                    :` ),
           ls_meta-system, '/', ls_meta-client.
  WRITE: / lcl_t=>ui( d = `Erzeugt                          :` e = `Created                          :` ),
           ls_meta-created_at, ls_meta-created_by.
  WRITE: / lcl_t=>ui( d = `BC-Set                           :` e = `BC set                           :` ), lv_id.
  WRITE: / lcl_t=>ui( d = `Paket                            :` e = `Package                          :` ), p_bpack.
  IF p_btr IS NOT INITIAL.
    WRITE: / lcl_t=>ui( d = `Auftrag                          :` e = `Request                          :` ), p_btr.
  ENDIF.

* Ein Dokument, das schon beim Sammeln an die Grenze gestossen ist,
* beschreibt nicht den Zustand des Quellsystems. Daraus ein BC-Set zu
* bauen hiesse, eine Luecke mit auszuliefern.
  IF ls_meta-truncated = abap_true.
    SKIP.
    WRITE: / lcl_t=>ui( d = `ACHTUNG: Das Dokument ist unvollstaendig (Kapitelgrenze erreicht).`
                        e = `CAUTION: the document is incomplete (chapter limit reached).` ).
    WRITE: / lcl_t=>ui( d = `Einzelne Objekte koennen fehlen. Export ohne Begrenzung wiederholen.`
                        e = `Individual objects may be missing. Repeat the export without a limit.` ).
  ENDIF.

  IF p_btest = abap_true.
    SKIP.
    WRITE: / lcl_t=>ui( d = `TESTLAUF - es wird nichts angelegt.`
                        e = `TEST RUN - nothing is created.` ).
  ENDIF.

  DATA(lo_bcset) = NEW lcl_bcset( iv_id   = lv_id
                                  iv_text = CONV string( p_btext )
                                  iv_pack = p_bpack
                                  iv_tr   = p_btr
                                  iv_test = p_btest ).

  DATA(lv_ok) = lo_bcset->build( lo_doc ).

  SKIP.
  WRITE: / lcl_t=>ui( d = `Tabellen                         :` e = `Tables                           :` ), lo_bcset->get_tables( ).
  WRITE: / lcl_t=>ui( d = `Datensaetze                      :` e = `Records                          :` ), lo_bcset->get_records( ).
  WRITE: / lcl_t=>ui( d = `Feldwerte                        :` e = `Field values                     :` ), lo_bcset->get_values( ).
  IF lo_bcset->get_clidep( ) = abap_true.
    WRITE: / lcl_t=>ui( d = `Mandantenabhaengig               : ja`
                        e = `Client-dependent                 : yes` ).
  ENDIF.

  SKIP.
* Spaltenbreite ueber feste Felder, nicht ueber Offset/Laenge auf dem
* String: ls_log-tab(30) verlangt 30 Zeichen und bricht ab, sobald der
* Name kuerzer ist - STRING_LENGTH_TOO_LARGE.
  DATA lv_ltab TYPE char30.
  DATA lv_lact TYPE char20.
  LOOP AT lo_bcset->get_log( ) INTO DATA(ls_log).
    lv_ltab = ls_log-tab.
    lv_lact = ls_log-action.
    WRITE: / lv_ltab, lv_lact, ls_log-text.
  ENDLOOP.

* Die Fehlliste entsteht unabhaengig vom Testlauf: gerade im Testlauf
* will man wissen, was im Zielsystem fehlt, bevor man etwas anlegt.
  DATA(lt_miss) = lo_bcset->get_missing( ).
  IF p_breq = abap_true.
    SKIP.
    IF lt_miss IS INITIAL.
      WRITE: / lcl_t=>ui( d = `Keine fehlenden Objekte - keine Fehlliste noetig.`
                          e = `No missing objects - no request list needed.` ).
    ELSE.
      DATA(lv_req) = lcl_request=>render(
                       it_miss   = lt_miss
                       iv_source = |{ ls_meta-system }/{ ls_meta-client }| ).
      PERFORM write_request USING lv_req.
      WRITE: / lcl_t=>ui( d = `Fehlliste                        :`
                          e = `Request list                     :` ), lines( lt_miss ),
               lcl_t=>ui( d = `Objekte` e = `objects` ).
      LOOP AT lt_miss INTO DATA(ls_miss).
        DATA lv_mtyp TYPE char6.
        DATA lv_mnam TYPE char30.
        lv_mtyp = ls_miss-type.
        lv_mnam = ls_miss-name.
        WRITE: / '   ', lv_mtyp, lv_mnam, ls_miss-activity.
      ENDLOOP.
    ENDIF.
  ENDIF.

  SKIP.
  IF p_btest = abap_true.
    WRITE: / lcl_t=>ui( d = `Testlauf beendet. Zum Anlegen den Testlauf abwaehlen.`
                        e = `Test run finished. Deselect the test run to create it.` ).
  ELSEIF lv_ok = abap_true.
    WRITE: / lcl_t=>ui( d = `BC-Set angelegt. Es ist noch nichts aktiviert -`
                        e = `BC set created. Nothing has been activated yet -` ).
    WRITE: / lcl_t=>ui( d = `das Customizing entsteht erst mit SCPR20.`
                        e = `the customizing is written only by SCPR20.` ).
  ELSE.
    WRITE: / lcl_t=>ui( d = `BC-Set nicht angelegt. Siehe Protokoll oben.`
                        e = `BC set not created. See the log above.` ).
  ENDIF.

ENDFORM.

*----------------------------------------------------------------------*
* Fehlliste schreiben
*----------------------------------------------------------------------*
* Ziel ist dasselbe Medium wie die Eingabedatei: liegt das Dokument auf
* dem Applikationsserver, landet auch der Auftrag dort. Ohne
* Dateinamen wird nur angezeigt - eine Liste, die man abschreiben kann,
* ist besser als eine Datei, die niemand angefordert hat.
FORM write_request USING iv_xml TYPE string.

  DATA lv_file TYPE string.
  DATA lv_x    TYPE xstring.
  DATA lt_bin  TYPE solix_tab.
  DATA lv_len  TYPE i.

  lv_file = p_brfil.
  CONDENSE lv_file.
  IF lv_file IS INITIAL.
    WRITE: / lcl_t=>ui( d = `Keine Datei fuer die Fehlliste angegeben - nur Anzeige.`
                        e = `No file given for the request list - display only.` ).
    RETURN.
  ENDIF.

  lv_x = cl_abap_codepage=>convert_to( iv_xml ).

  IF p_bsrv = abap_true.
    OPEN DATASET lv_file FOR OUTPUT IN BINARY MODE.
    IF sy-subrc <> 0.
      WRITE: / lcl_t=>ui( d = `Serverdatei nicht schreibbar    :`
                          e = `Server file cannot be written    :` ), lv_file.
      RETURN.
    ENDIF.
    TRANSFER lv_x TO lv_file.
    CLOSE DATASET lv_file.
    WRITE: / lcl_t=>ui( d = `Fehlliste geschrieben           :`
                        e = `Request list written             :` ), lv_file.
    RETURN.
  ENDIF.

  IF sy-batch = abap_true.
    WRITE: / lcl_t=>ui( d = `Im Hintergrund gibt es keinen PC-Zugriff.`
                        e = `There is no PC access in the background.` ).
    RETURN.
  ENDIF.

  CALL FUNCTION 'SCMS_XSTRING_TO_BINARY'
    EXPORTING  buffer     = lv_x
    IMPORTING  output_length = lv_len
    TABLES     binary_tab = lt_bin.

  cl_gui_frontend_services=>gui_download(
    EXPORTING  filename     = lv_file
               filetype     = 'BIN'
               bin_filesize = lv_len
    CHANGING   data_tab     = lt_bin
    EXCEPTIONS OTHERS       = 1 ).
  IF sy-subrc <> 0.
    WRITE: / lcl_t=>ui( d = `Fehlliste nicht schreibbar      :`
                        e = `Request list cannot be written   :` ), lv_file.
    RETURN.
  ENDIF.
  WRITE: / lcl_t=>ui( d = `Fehlliste geschrieben           :`
                      e = `Request list written             :` ), lv_file.

ENDFORM.

*----------------------------------------------------------------------*
* Value help for the structure ID
*----------------------------------------------------------------------*
FORM f4_struktur.

* The columns deliberately carry DDIC types: the value help derives its
* column headings from them. The node count is appended to the text
* because there is no data element with a usable label for it - and it is
* the most important discriminator when several structures share a name.

  TYPES: BEGIN OF ty_f4,
           tree_id TYPE ttree-id,
           text    TYPE tnodeimgt-text,
           type    TYPE ttree-type,
           comp    TYPE tnodeimg-component,
           ldate   TYPE ttree-ldate,
         END OF ty_f4.

  DATA lt_f4      TYPE STANDARD TABLE OF ty_f4.
  DATA ls_f4      TYPE ty_f4.
  DATA lt_ret     TYPE STANDARD TABLE OF ddshretval.
  DATA lv_pattern TYPE string.
  DATA lr_tree    TYPE RANGE OF ttree-id.

  IF p_srch IS INITIAL.
    lv_pattern = '%'.
  ELSE.
    lv_pattern = |%{ p_srch }%|.
  ENDIF.

  SELECT n~tree_id AS tree_id, t~text AS text, n~component AS comp
    FROM tnodeimg AS n
    INNER JOIN tnodeimgt AS t
      ON t~tree_id = n~tree_id AND t~node_id = n~node_id
    WHERE n~parent_id = @space
      AND t~spras     = @p_langu
      AND t~text      LIKE @lv_pattern
    INTO CORRESPONDING FIELDS OF TABLE @lt_f4
    UP TO 500 ROWS.

  SORT lt_f4 BY text tree_id.
  DELETE ADJACENT DUPLICATES FROM lt_f4 COMPARING tree_id.

  IF lt_f4 IS INITIAL.
    RETURN.
  ENDIF.

  LOOP AT lt_f4 INTO ls_f4.
    APPEND VALUE #( sign = 'I' option = 'EQ' low = ls_f4-tree_id ) TO lr_tree.
  ENDLOOP.

  " Structure type and change date
  SELECT id, type, ldate FROM ttree
    WHERE id IN @lr_tree
    INTO TABLE @DATA(lt_tree).

  " Node count per structure - without FOR ALL ENTRIES, because aggregates
  " are not allowed with it
  SELECT tree_id, COUNT(*) AS cnt FROM tnodeimg
    WHERE tree_id IN @lr_tree
    GROUP BY tree_id
    INTO TABLE @DATA(lt_cnt).

  LOOP AT lt_f4 INTO ls_f4.
    DATA(lv_idx) = sy-tabix.
    READ TABLE lt_tree INTO DATA(ls_tree) WITH KEY id = ls_f4-tree_id.
    IF sy-subrc = 0.
      ls_f4-type  = ls_tree-type.
      ls_f4-ldate = ls_tree-ldate.
    ENDIF.
    READ TABLE lt_cnt INTO DATA(ls_cnt) WITH KEY tree_id = ls_f4-tree_id.
    IF sy-subrc = 0.
      ls_f4-text = |{ ls_f4-text } ({ ls_cnt-cnt } Knoten)|.
    ENDIF.
    MODIFY lt_f4 FROM ls_f4 INDEX lv_idx.
  ENDLOOP.

  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING
      retfield        = 'TREE_ID'
      dynpprog        = sy-repid
      dynpnr          = sy-dynnr
      dynprofield     = 'P_TREE'
      value_org       = 'S'
    TABLES
      value_tab       = lt_f4
      return_tab      = lt_ret
    EXCEPTIONS
      parameter_error = 1
      no_values_found = 2
      OTHERS          = 3.

ENDFORM.

*----------------------------------------------------------------------*
* Value help for the project
*----------------------------------------------------------------------*
FORM f4_projekt.

  TYPES: BEGIN OF ty_p,
           project_id TYPE tproject-project_id,
           title      TYPE tprojectt-title,
           responsibl TYPE tproject-responsibl,
           class      TYPE tproject-class,
           ldate      TYPE tproject-ldate,
         END OF ty_p.

  DATA lt_p   TYPE STANDARD TABLE OF ty_p.
  DATA lt_ret TYPE STANDARD TABLE OF ddshretval.

  SELECT p~project_id AS project_id, t~title AS title,
         p~responsibl AS responsibl, p~class AS class, p~ldate AS ldate
    FROM tproject AS p
    LEFT OUTER JOIN tprojectt AS t
      ON t~project_id = p~project_id AND t~langu = @p_langu
    INTO CORRESPONDING FIELDS OF TABLE @lt_p
    UP TO 500 ROWS.

  SORT lt_p BY project_id.
  DELETE ADJACENT DUPLICATES FROM lt_p COMPARING project_id.

  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING
      retfield        = 'PROJECT_ID'
      dynpprog        = sy-repid
      dynpnr          = sy-dynnr
      dynprofield     = 'P_PROJ'
      value_org       = 'S'
    TABLES
      value_tab       = lt_p
      return_tab      = lt_ret
    EXCEPTIONS
      parameter_error = 1
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

*----------------------------------------------------------------------*
* Write the file to the PC
*
* The content is converted to UTF-8 first and written in binary mode. A
* text download would translate the characters into the frontend code
* page, and that is where umlauts and special characters get lost.
*----------------------------------------------------------------------*
*&---------------------------------------------------------------------*
*& FORM suggest_fname
*&---------------------------------------------------------------------*
FORM suggest_fname.

* Der Vorschlag wird bei jedem Bildaufbau neu gebildet, damit er dem
* Startknoten folgt: wer die IMG-Struktur aendert, sieht den Dateinamen
* sofort mitwandern. Ueberschrieben wird das Feld nur, solange darin
* noch der vorige Vorschlag steht - ein selbst gewaehlter Name bleibt.
  DATA lv_new  TYPE string.
  DATA lv_part TYPE string.

  PERFORM fname_object CHANGING lv_part.
  lv_new = |documizer_{ sy-sysid }{ lv_part }_{ sy-datum }_{ sy-uzeit }|.

  IF p_fname IS INITIAL OR p_fname = gv_fauto.
    p_fname = lv_new.
  ENDIF.
  gv_fauto = lv_new.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM fname_object
*&---------------------------------------------------------------------*
FORM fname_object CHANGING cv_part TYPE string.

* Der Startpunkt ist entweder eine IMG-Struktur oder ein Projekt. Bei
* der Textsuche gibt es keinen Namen, den man in einen Dateinamen
* schreiben moechte - der Suchbegriff ist Prosa.
  DATA lv_name TYPE string.

  CLEAR cv_part.
  IF p_tree IS NOT INITIAL.
    lv_name = to_lower( CONV string( p_tree ) ).
  ELSEIF p_proj IS NOT INITIAL.
    lv_name = to_lower( CONV string( p_proj ) ).
  ELSE.
    RETURN.
  ENDIF.

* Ein Namensraum bringt Schraegstriche mit, und die trennen im
* Dateisystem Verzeichnisse.
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
    cv_base = |documizer_{ sy-sysid }{ lv_part }_{ sy-datum }_{ sy-uzeit }|.
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

*----------------------------------------------------------------------*
* Helper routine: search structures when no GUID is known
*----------------------------------------------------------------------*
FORM search_structures.

  DATA lv_pattern TYPE string.

  IF p_srch IS INITIAL.
    WRITE: / lcl_t=>ui( d = `Bitte Struktur-GUID (P_TREE) oder Suchbegriff (P_SRCH) angeben.` e = `Please specify a structure GUID (P_TREE) or a search term (P_SRCH).` ).
    RETURN.
  ENDIF.

  lv_pattern = |%{ p_srch }%|.

  SELECT n~tree_id, t~text
    FROM tnodeimg AS n
    INNER JOIN tnodeimgt AS t
      ON t~tree_id = n~tree_id AND t~node_id = n~node_id
    WHERE n~parent_id = @space
      AND t~spras     = @p_langu
      AND t~text      LIKE @lv_pattern
    INTO TABLE @DATA(lt_hits)
    UP TO 50 ROWS.

  IF lines( lt_hits ) = 0.
    WRITE: / lcl_t=>ui( d = `Keine IMG-Struktur gefunden zu:` e = `No IMG structure found for:` ), p_srch.
    RETURN.
  ENDIF.

  WRITE: / lcl_t=>ui( d = `Gefundene IMG-Strukturen - GUID in P_TREE übernehmen` e = `IMG structures found - copy the GUID into P_TREE` ).
  ULINE.
  LOOP AT lt_hits INTO DATA(ls_hit).
    WRITE: / ls_hit-tree_id, ls_hit-text.
  ENDLOOP.

ENDFORM.

*----------------------------------------------------------------------*
* Main flow
*----------------------------------------------------------------------*
START-OF-SELECTION.

* The document speaks the output language, including its own headings.
  lcl_t=>set_lang( p_langu ).

* Der BC-Set-Lauf liest ein fertiges Dokument und sammelt nichts. Er
* steht deshalb vor allem anderen und kehrt danach zurueck.
  IF p_bcs = abap_true.
    PERFORM bcset.
    RETURN.
  ENDIF.

  IF p_tree IS INITIAL.
    PERFORM search_structures.
    RETURN.
  ENDIF.

  DATA(lo_collector) = NEW lcl_collector_img( iv_tree_id = p_tree
                                              iv_langu   = p_langu
                                              iv_depth   = p_depth
                                              iv_maxnod  = p_maxnod
                                              iv_subs    = p_subs
                                              iv_doku    = p_doku
                                              iv_obj     = p_obj
                                              iv_calls   = p_calls
                                              iv_nosap   = p_nosap
                                              iv_proj    = p_proj
                                              iv_onlypr  = p_onlypr
                                              iv_pstat   = p_pstat
                                              iv_pmemo   = p_pmemo
                                              iv_falb    = p_falb
                                              iv_flang   = p_flang
                                              io_cust    = COND #(
                                                WHEN p_data = abap_true
                                                THEN NEW lcl_cust( iv_custom = p_cust
                                                                   iv_maxrow = p_maxrow
                                                                   iv_hist   = p_hist ) ) ).

  DATA lo_coll TYPE REF TO lif_docu_collector.
  lo_coll = lo_collector.

  DATA(lo_doc) = lo_coll->collect( ).

  DATA lo_renderer TYPE REF TO lif_docu_renderer.
  lo_renderer = NEW lcl_renderer_xml( ).

* XML is only produced when it is actually needed: for the output, for
* the download or for the roundtrip self-test.
  DATA lv_xml TYPE string.
  IF p_xml = abap_true OR p_rtest = abap_true
     OR ( p_down = abap_true AND p_xml = abap_true ).
    lv_xml = lo_renderer->render( lo_doc ).
  ENDIF.

  WRITE: / lcl_t=>ui( d = `Documizer - IMG-Collector (ohne Dateninhalte)` e = `Documizer - IMG collector` ).
  ULINE.
  WRITE: / lcl_t=>ui( d = `Struktur                         :` e = `Structure                        :` ), p_tree.
  DATA(ls_docmeta) = lo_doc->get_meta( ).

  WRITE: / lcl_t=>ui( d = `Kapitel erzeugt                  :` e = `Chapters created                 :` ), lo_collector->get_stat_nodes( ).
  WRITE: / lcl_t=>ui( d = `Kapitel im gewaehlten Umfang     :` e = `Chapters in the selected scope   :` ), ls_docmeta-node_total.
  IF p_maxnod = 0.
    WRITE: / lcl_t=>ui( d = `Limit                            : ohne Begrenzung` e = `Limit                            : none` ).
  ELSE.
    WRITE: / lcl_t=>ui( d = `Limit                            :` e = `Limit                            :` ), p_maxnod.
  ENDIF.
  WRITE: / lcl_t=>ui( d = `davon Aktivitäten                :` e = `of these activities              :` ), lo_collector->get_stat_activities( ).
  WRITE: / lcl_t=>ui( d = `mit Standarddokumentation        :` e = `with standard documentation      :` ), lo_collector->get_stat_docu( ).
  IF p_falb = abap_true.
    WRITE: / lcl_t=>ui( d = `davon in Ersatzsprache           :` e = `of these in the fallback language:` ), lo_collector->get_stat_fallback( ).
  ENDIF.
  WRITE: / lcl_t=>ui( d = `zugeordnete Objekte              :` e = `assigned objects                 :` ), lo_collector->get_stat_objects( ).
  IF p_calls = abap_true.
    WRITE: / lcl_t=>ui( d = `mit ausgehenden Aufrufen         :` e = `with outgoing references         :` ), lo_collector->get_stat_calls( ).
  ENDIF.
  IF p_proj IS NOT INITIAL.
    WRITE: / lcl_t=>ui( d = `Kapitel mit Projektdaten         :` e = `chapters with project data       :` ), lo_collector->get_stat_project( ).
    IF p_onlypr = abap_true AND p_maxnod > 0.
      WRITE: / lcl_t=>ui( d = `Hinweis: Kapitelgrenze im Projektmodus ausgesetzt,` e = `Note: chapter limit suspended in project mode,` ),
               lcl_t=>ui( d = `sonst wuerden tiefe Projektknoten nicht gefunden.`
                          e = `deep project nodes would not be found otherwise.` ).
    ENDIF.
  ENDIF.
  IF lv_xml IS NOT INITIAL.
    WRITE: / lcl_t=>ui( d = `XML-Zeichen                      :` e = `XML characters                   :` ), strlen( lv_xml ).
  ENDIF.

  IF ls_docmeta-truncated = abap_true.
    WRITE: / lcl_t=>ui( d = `ACHTUNG: Limit erreicht, Dokument unvollständig.` e = `CAUTION: limit reached, document is incomplete.` ).
  ENDIF.

  " Check the roundtrip against real data, not just against a sample
  IF p_rtest = abap_true.
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
    ELSE.
      WRITE: / lcl_t=>ui( d = `HTML-Anzeige im Hintergrund nicht möglich.` e = `HTML display not possible in the background.` ).
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
