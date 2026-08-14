REPORT zdocumizer_dev.

************************************************************************
* Documizer - step 5: ABAP package / developer documentation
*
* The second pillar next to the IMG report. The input is a start package;
* from there all subpackages are determined recursively, the development
* objects they contain are read and arranged into chapters.
*
* Chapter model, interfaces, XML renderer and parser are identical to
* ZDOCUMIZER_IMG - the price for keeping every report runnable after a
* copy/paste into SE38. In the target design they live as global classes
* in ZCONS_DOCUMIZER_CORE.
*
* Standard interfaces used:
*   CL_PAK_PACKAGE_QUERIES=>GET_ALL_SUBPACKAGES        packages recursively
*   CL_PAK_PACKAGE_QUERIES=>GET_DEV_OBJECT_TADIR_KEYS  objects per package
*   DOCU_GET                                           object documentation
*   DD03L, SEOCOMPO                                    detail information
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

CONSTANTS gc_version TYPE string VALUE '1.0'.

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

            WHEN 'source'.
              lv_target = 'source'.

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
              WHEN 'source'.
                IF lo_current IS BOUND.
                  lo_current->set_source( lv_value ).
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

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE gv_blk1.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tpack FOR FIELD p_pack.
    PARAMETERS p_pack TYPE tdevc-devclass OBLIGATORY.
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
    SELECTION-SCREEN COMMENT 1(30) gv_tmaxu FOR FIELD p_maxuse.
    PARAMETERS p_maxuse TYPE i DEFAULT 50.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK b2.

SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE gv_blk3.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_txml FOR FIELD p_xml.
    PARAMETERS p_xml AS CHECKBOX DEFAULT 'X'.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_thtml FOR FIELD p_html.
    PARAMETERS p_html AS CHECKBOX.
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
    SELECTION-SCREEN COMMENT 1(24) gv_tdsrv FOR FIELD p_dsrv.
    PARAMETERS p_dsrv AS CHECKBOX.
    SELECTION-SCREEN COMMENT 29(18) gv_tsrv FOR FIELD p_srv.
    PARAMETERS p_srv TYPE char128 LOWER CASE VISIBLE LENGTH 30.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK b3.

INITIALIZATION.
* Screen labels live in the source, not in the text pool, so that a copied
* report is readable in any system. English is the default; German is used
* only when the user is logged on in German.
  IF sy-langu = 'D'.
    gv_blk1  = 'Startpaket'.
    gv_blk2  = 'Umfang'.
    gv_blk3  = 'Ausgabe'.
    gv_tpack = 'Paket'.
    gv_trec  = 'Unterpakete rekursiv'.
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
    gv_tmaxu = 'Max. Verwendungen je Objekt'.
    gv_txml  = 'XML erzeugen/ausgeben'.
    gv_thtml = 'HTML erzeugen/anzeigen'.
    gv_trt   = 'Roundtrip prüfen'.
    gv_tdown = 'Download auf PC'.
    gv_tpath = 'Verzeichnis'.
    gv_tdsrv = 'Ablage Appl.-Server'.
    gv_tsrv  = 'Verzeichnis'.
    %_s_objtyp_%_app_%-text = 'Objekttyp'.
    %_s_objnam_%_app_%-text = 'Objektname'.
  ELSE.
    gv_blk1  = 'Start package'.
    gv_blk2  = 'Scope'.
    gv_blk3  = 'Output'.
    gv_tpack = 'Package'.
    gv_trec  = 'Include subpackages'.
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
    gv_tmaxu = 'Max. entries per object'.
    gv_txml  = 'Create/show XML'.
    gv_thtml = 'Create/show HTML'.
    gv_trt   = 'Check roundtrip'.
    gv_tdown = 'Download to PC'.
    gv_tpath = 'Directory'.
    gv_tdsrv = 'Store on app server'.
    gv_tsrv  = 'Directory'.
* Select-options take their label from the text pool; the COMMENT approach
* used for the other fields does not apply. The generated fields
* %_<name>_%_app_%-text allow setting it at runtime.
    %_s_objtyp_%_app_%-text = 'Object type'.
    %_s_objnam_%_app_%-text = 'Object name'.
  ENDIF.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_path.
  PERFORM f4_verzeichnis.

*----------------------------------------------------------------------*
* lcl_renderer_html
*----------------------------------------------------------------------*
CLASS lcl_renderer_html DEFINITION.
  PUBLIC SECTION.
    INTERFACES lif_docu_renderer.
  PRIVATE SECTION.
    DATA mv_html TYPE string.
    METHODS add IMPORTING iv_text TYPE string.
    METHODS esc IMPORTING iv_text TYPE string RETURNING VALUE(rv_text) TYPE string.
    METHODS write_chapter IMPORTING io_chapter TYPE REF TO lcl_chapter.
    METHODS write_toc     IMPORTING io_chapter TYPE REF TO lcl_chapter.
ENDCLASS.

CLASS lcl_renderer_html IMPLEMENTATION.

  METHOD add.
    mv_html = |{ mv_html }{ iv_text }{ cl_abap_char_utilities=>newline }|.
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
    add( '.ref{color:#666;font-size:11px;margin:2px 0}' ).
    add( '.warn{color:#a00;font-weight:bold}' ).
    add( 'ul.toc{line-height:1.6}' ).
    add( 'pre.src{background:#fbfbf5;border:1px solid #ddd;padding:8px;' &&
         'font-family:Consolas,monospace;font-size:11px;overflow-x:auto;' &&
         'white-space:pre}' ).
    add( '</style></head><body>' ).

    add( |<h1>{ lcl_t=>t( d = lcl_t=>ui( d = `Documizer - Entwicklerdokumentation` e = `Documizer - developer documentation` )
                          e = 'Documizer - developer documentation' ) }</h1>| ).

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

    IF ls_meta-truncated = abap_true.
      add( |<p class="warn">{ lcl_t=>t(
             d = |Achtung: Von { ls_meta-node_total } Objekten sind nur | &&
                 |{ ls_meta-node_limit } enthalten. Das Dokument ist | &&
                 |unvollständig.|
             e = |Caution: of { ls_meta-node_total } objects only | &&
                 |{ ls_meta-node_limit } are contained. The document is | &&
                 |incomplete.| ) }</p>| ).
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
      add( |<div class="doc">{ esc( io_chapter->get_documentation( ) ) }</div>| ).
    ENDIF.

    IF io_chapter->get_source( ) IS NOT INITIAL.
      add( |<pre class="src">{ esc( io_chapter->get_source( ) ) }</pre>| ).
    ENDIF.

    LOOP AT io_chapter->get_objects( ) INTO DATA(lo_obj).
      IF lo_obj->get_note( ) IS NOT INITIAL.
        add( |<p class="ref">{ esc( lo_obj->get_note( ) ) }</p>| ).
      ENDIF.
      IF lines( lo_obj->get_fields( ) ) > 0.
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
      IMPORTING iv_pack   TYPE devclass
                iv_recur  TYPE abap_bool
                iv_local  TYPE abap_bool
                iv_langu  TYPE sy-langu
                iv_maxobj TYPE i
                iv_doku   TYPE abap_bool
                iv_detail TYPE abap_bool
                iv_src    TYPE abap_bool
                iv_maxsrc TYPE i
                iv_used   TYPE abap_bool
                iv_maxuse TYPE i
                iv_falb   TYPE abap_bool
                iv_flang  TYPE sy-langu
                iv_calls  TYPE abap_bool.
    METHODS get_stat_packages RETURNING VALUE(rv) TYPE i.
    METHODS get_stat_objects  RETURNING VALUE(rv) TYPE i.
    METHODS get_stat_total    RETURNING VALUE(rv) TYPE i.
    METHODS get_stat_docu     RETURNING VALUE(rv) TYPE i.
    METHODS get_stat_source   RETURNING VALUE(rv) TYPE i.
    METHODS get_stat_usage    RETURNING VALUE(rv) TYPE i.
    METHODS get_stat_fallback RETURNING VALUE(rv) TYPE i.
    METHODS get_stat_calls    RETURNING VALUE(rv) TYPE i.
  PRIVATE SECTION.
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
    DATA mv_maxuse TYPE i.
    DATA mv_calls  TYPE abap_bool.
    DATA mv_falb   TYPE abap_bool.
    DATA mv_flang  TYPE sy-langu.
    DATA mv_n_falb TYPE i.
    DATA mv_last_lang TYPE sy-langu.
    DATA mv_note   TYPE string.
    DATA mv_n_use  TYPE i.
    DATA mv_n_call TYPE i.
    DATA mv_n_src  TYPE i.
    DATA mv_n_pack TYPE i.
    DATA mv_n_obj  TYPE i.
    DATA mv_n_tot  TYPE i.
    DATA mv_n_docu TYPE i.

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
    METHODS append_report
      IMPORTING iv_prog   TYPE syrepid
      CHANGING  ct_source TYPE string_table.
    METHODS add_usages
      IMPORTING iv_name    TYPE sobj_name
                io_chapter TYPE REF TO lcl_chapter.
    METHODS add_calls
      IMPORTING iv_name    TYPE sobj_name
                io_chapter TYPE REF TO lcl_chapter.
    METHODS pack_reason
      IMPORTING iv_subrc        TYPE sy-subrc
      RETURNING VALUE(rv_reason) TYPE string.
ENDCLASS.

CLASS lcl_collector_dev IMPLEMENTATION.

  METHOD constructor.
    mv_pack   = iv_pack.
    mv_recur  = iv_recur.
    mv_local  = iv_local.
    mv_langu  = iv_langu.
    mv_maxobj = iv_maxobj.
    mv_doku   = iv_doku.
    mv_detail = iv_detail.
    mv_src    = iv_src.
    mv_maxsrc = iv_maxsrc.
    mv_used   = iv_used.
    mv_calls  = iv_calls.
    mv_maxuse = iv_maxuse.
    mv_falb   = iv_falb.
    mv_flang  = iv_flang.
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
      WHEN OTHERS. rv_title = |{ lcl_t=>t( d = `Objekttyp` e = `Object type` ) } { iv_type }|.
    ENDCASE.
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

  METHOD read_source.

    DATA lt_src  TYPE string_table.
    DATA lt_incl TYPE STANDARD TABLE OF progname.
    DATA lv_prog TYPE syrepid.
    DATA lv_i    TYPE i.

    CASE iv_type.

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
        " The name of the class pool is the object name padded to 30
        " characters with equals signs, plus CP.
        lv_prog = iv_name.
        lv_i = strlen( iv_name ).
        WHILE lv_i < 30.
          lv_prog = |{ lv_prog }=|.
          lv_i = lv_i + 1.
        ENDWHILE.
        lv_prog = |{ lv_prog }CP|.
        CALL FUNCTION 'RS_GET_ALL_INCLUDES'
          EXPORTING
            program             = lv_prog
            with_class_includes = abap_true
          TABLES
            includetab          = lt_incl
          EXCEPTIONS
            not_existent        = 1
            no_program          = 2
            OTHERS              = 3.
        LOOP AT lt_incl INTO DATA(ls_i2).
          append_report( EXPORTING iv_prog = ls_i2
                         CHANGING  ct_source = lt_src ).
        ENDLOOP.

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

      WHEN OTHERS.
        RETURN.

    ENDCASE.

    IF lt_src IS INITIAL.
      RETURN.
    ENDIF.

    DATA lv_n TYPE i.
    LOOP AT lt_src INTO DATA(lv_line).
      lv_n = lv_n + 1.
      IF mv_maxsrc > 0 AND lv_n > mv_maxsrc.
        rv_source = |{ rv_source }{ cl_abap_char_utilities=>newline }| &&
                    |* ... gekürzt bei { mv_maxsrc } Zeilen, | &&
                    |insgesamt { lines( lt_src ) } Zeilen|.
        EXIT.
      ENDIF.
      IF rv_source IS INITIAL.
        rv_source = lv_line.
      ELSE.
        rv_source = |{ rv_source }{ cl_abap_char_utilities=>newline }{ lv_line }|.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD add_calls.

    " Outgoing references - the counterpart to the where-used list. Neither
    " CROSS nor WBCROSSGT carries a secondary index for this direction, so
    " the read is a scan. On HANA that is acceptable for a column store, but
    " it is the reason this option is switched off by default.

    TYPES: BEGIN OF ty_call,
             rank TYPE i,
             what TYPE string,
             kind TYPE string,
           END OF ty_call.

    DATA lt_call TYPE STANDARD TABLE OF ty_call.
    DATA ls_call TYPE ty_call.
    DATA lv_max  TYPE i.

    lv_max = mv_maxuse.
    IF lv_max <= 0.
      lv_max = 100000.
    ENDIF.

    DATA lv_prog TYPE cross-prog.
    lv_prog = iv_name.
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

    lv_like = |{ iv_name }%|.
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
           END OF ty_use.
    DATA lt_use TYPE STANDARD TABLE OF ty_use.
    DATA ls_use TYPE ty_use.
    DATA lv_max TYPE i.

    lv_max = mv_maxuse.
    IF lv_max <= 0.
      lv_max = 100000.
    ENDIF.

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
    DELETE ADJACENT DUPLICATES FROM lt_use COMPARING where.

    DATA(lo_u) = NEW lcl_object( iv_type = 'USAGE'
                                 iv_name = CONV string( iv_name ) ).

    IF mv_maxuse > 0 AND lines( lt_use ) >= mv_maxuse.
      lo_u->set_note( |{ lcl_t=>t( d = `Verwendungsnachweis` e = `Where-used list` ) }| &&
                      | { lcl_t=>t( d = `(gekürzt bei` e = `(truncated at` ) }| &&
                      | { mv_maxuse })| ).
      lo_u->set_truncated( abap_true ).
    ELSE.
      lo_u->set_note( lcl_t=>t( d = 'Verwendungsnachweis' e = 'Where-used list' ) ).
    ENDIF.
    lo_u->set_row_count( lines( lt_use ) ).

    LOOP AT lt_use INTO ls_use.
      lo_u->add_field( VALUE ty_field( name     = ls_use-where
                                       rollname = ls_use-kind ) ).
    ENDLOOP.

    io_chapter->add_object( lo_u ).
    mv_n_use = mv_n_use + 1.

  ENDMETHOD.

  METHOD add_details.

    DATA lv_tab TYPE dd03l-tabname.
    DATA lv_cls TYPE seocompo-clsname.

    CASE iv_type.

      WHEN 'TABL' OR 'VIEW'.
        lv_tab = iv_name.
        SELECT fieldname, rollname, keyflag FROM dd03l
          WHERE tabname = @lv_tab AND as4local = 'A' AND fieldname NOT LIKE '.%'
          ORDER BY position
          INTO TABLE @DATA(lt_f).
        IF lt_f IS INITIAL.
          RETURN.
        ENDIF.
        DATA(lo_o1) = NEW lcl_object( iv_type = CONV string( iv_type )
                                      iv_name = CONV string( iv_name ) ).
        lo_o1->set_note( lcl_t=>t( d = 'Feldliste' e = 'Field list' ) ).
        LOOP AT lt_f INTO DATA(ls_f).
          lo_o1->add_field( VALUE ty_field(
            name     = ls_f-fieldname
            rollname = ls_f-rollname
            keyflag  = COND #( WHEN ls_f-keyflag = 'X' THEN abap_true ELSE abap_false ) ) ).
        ENDLOOP.
        io_chapter->add_object( lo_o1 ).

      WHEN 'CLAS' OR 'INTF'.
        lv_cls = iv_name.
        SELECT cmpname, cmptype FROM seocompo
          WHERE clsname = @lv_cls
          ORDER BY cmptype, cmpname
          INTO TABLE @DATA(lt_c).
        IF lt_c IS INITIAL.
          RETURN.
        ENDIF.
        DATA(lo_o2) = NEW lcl_object( iv_type = CONV string( iv_type )
                                      iv_name = CONV string( iv_name ) ).
        lo_o2->set_note( lcl_t=>t( d = 'Komponenten' e = 'Components' ) ).
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
        io_chapter->add_object( lo_o2 ).

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

      WHEN 'DDLS'.
        " Dependencies of the CDS view - the objects it consumes
        DATA lv_ddl TYPE ddldependency-ddlname.
        lv_ddl = iv_name.
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

    ENDCASE.

  ENDMETHOD.

  METHOD lif_docu_collector~collect.

    DATA lt_packages TYPE cl_pak_package_queries=>tt_subpackage_info.
    DATA lt_tadir    TYPE cl_pak_package_queries=>tt_tadir_data.
    DATA lt_all      TYPE STANDARD TABLE OF devclass.
    DATA lv_trunc    TYPE abap_bool.
    DATA lv_cnt      TYPE i.

    ro_document = NEW lcl_document( ).

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
          add_usages( iv_name    = ls_tadir-object_name
                      io_chapter = lo_ochap ).
        ENDIF.

        IF mv_calls = abap_true.
          add_calls( iv_name    = ls_tadir-object_name
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
      truncated  = lv_trunc
      node_limit = mv_maxobj
      node_total = mv_n_tot ) ).

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

ENDCLASS.

*----------------------------------------------------------------------*
* Output helper routines
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

  lv_file = |{ lv_dir }documizer_dev_{ sy-sysid }_{ sy-datum }_{ sy-uzeit }.{ iv_ext }|.
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
  DATA lv_msg  TYPE string.

  lv_dir = p_srv.
  CONDENSE lv_dir.
  IF lv_dir IS INITIAL.
    RETURN.
  ENDIF.

  IF substring( val = lv_dir off = strlen( lv_dir ) - 1 len = 1 ) <> '/'.
    lv_dir = |{ lv_dir }/|.
  ENDIF.

  lv_file = |{ lv_dir }documizer_dev_{ sy-sysid }_{ sy-datum }_{ sy-uzeit }.{ iv_ext }|.
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
* Main flow
*----------------------------------------------------------------------*
START-OF-SELECTION.

* The document speaks the output language, including its own headings.
  lcl_t=>set_lang( p_langu ).

  DATA(lo_collector) = NEW lcl_collector_dev( iv_pack   = p_pack
                                              iv_recur  = p_recur
                                              iv_local  = p_local
                                              iv_langu  = p_langu
                                              iv_maxobj = p_maxobj
                                              iv_doku   = p_doku
                                              iv_detail = p_detail
                                              iv_src    = p_src
                                              iv_maxsrc = p_maxsrc
                                              iv_used   = p_used
                                              iv_maxuse = p_maxuse
                                              iv_falb   = p_falb
                                              iv_flang  = p_flang
                                              iv_calls  = p_calls ).

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

  WRITE: / lcl_t=>ui( d = `Documizer - Entwicklerdokumentation` e = `Documizer - developer documentation` ).
  ULINE.
  WRITE: / lcl_t=>ui( d = `Startpaket                       :` e = `Start package                    :` ), p_pack.
  WRITE: / lcl_t=>ui( d = `Pakete                           :` e = `Packages                         :` ), lo_collector->get_stat_packages( ).
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

  IF ls_docmeta-truncated = abap_true.
    WRITE: / lcl_t=>ui( d = `ACHTUNG: Objektgrenze erreicht, Dokument unvollständig.` e = `CAUTION: object limit reached, document is incomplete.` ).
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
