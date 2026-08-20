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
    SELECTION-SCREEN COMMENT 1(30) gv_tstyp FOR FIELD p_stype.
    PARAMETERS p_stype TYPE char2 DEFAULT 'K' OBLIGATORY.
    SELECTION-SCREEN COMMENT 38(40) gv_tstyt.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tsval FOR FIELD p_sval.
    PARAMETERS p_sval TYPE tadir-obj_name OBLIGATORY.
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
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tmaxh FOR FIELD p_maxhit.
    PARAMETERS p_maxhit TYPE i DEFAULT 40.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tfsrc FOR FIELD p_fsrc.
    PARAMETERS p_fsrc AS CHECKBOX.
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
    gv_blk1  = 'Startpunkt'.
    gv_blk2  = 'Umfang'.
    gv_blk3  = 'Ausgabe'.
    gv_tstyp = 'Typ'.
    gv_tsval = 'Name (Paket, Report, ...)'.
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
    gv_tmaxh = 'Max. Fundstellen je Stelle'.
    gv_tfsrc = 'Fundstellen im ganzen Quelltext'.
    gv_txml  = 'XML erzeugen/ausgeben'.
    gv_thtml = 'HTML erzeugen/anzeigen'.
    gv_tfold = 'HTML einklappen ab Zeilen'.
    gv_trt   = 'Roundtrip prüfen'.
    gv_tdown = 'Download auf PC'.
    gv_tpath = 'Verzeichnis'.
    gv_tdsrv = 'Ablage Appl.-Server'.
    gv_tsrv  = 'Verzeichnis'.
    %_s_objtyp_%_app_%-text = 'Objekttyp'.
    %_s_objnam_%_app_%-text = 'Objektname'.
  ELSE.
    gv_blk1  = 'Start point'.
    gv_blk2  = 'Scope'.
    gv_blk3  = 'Output'.
    gv_tstyp = 'Type'.
    gv_tsval = 'Name (package, report, ...)'.
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
    gv_tmaxh = 'Max. occurrences per place'.
    gv_tfsrc = 'Occurrences in full source'.
    gv_txml  = 'Create/show XML'.
    gv_thtml = 'Create/show HTML'.
    gv_tfold = 'Collapse HTML from lines'.
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

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_stype.
  PERFORM f4_stype.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_sval.
  PERFORM f4_sval.

AT SELECTION-SCREEN OUTPUT.
* The plain code says little; the text next to it says what was picked.
  PERFORM stype_text USING p_stype CHANGING gv_tstyt.

AT SELECTION-SCREEN.
  PERFORM check_stype.

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
      FIND PCRE '^&[A-Z0-9_]+&$' IN lv_line.
      IF sy-subrc = 0.
        rv_html = |{ rv_html }<p class="sec">{ esc(
                    itf_section( substring( val = lv_line off = 1 len = lv_len - 2 ) ) ) }</p>|.
        CONTINUE.
      ENDIF.

      DATA lv_mark TYPE string.
      FIND FIRST OCCURRENCE OF PCRE '^&([A-Z0-9_]+)&\s*' IN lv_line
           SUBMATCHES lv_mark.
      IF sy-subrc = 0.
        REPLACE FIRST OCCURRENCE OF PCRE '^&[A-Z0-9_]+&\s*' IN lv_line WITH ''.
        rv_html = |{ rv_html }<p class="sec">{ esc( itf_section( lv_mark ) ) }</p>|.
        IF lv_line IS INITIAL.
          CONTINUE.
        ENDIF.
      ENDIF.

      lv_line = esc( lv_line ).

*     ITF markup. All two- to three-character markers are handled
*     generically, cross references <DS:...> come along; the closing
*     marker </> applies to every one of them.
      REPLACE ALL OCCURRENCES OF PCRE '&lt;DS:[^&]+&gt;' IN lv_line WITH '<b>'.
      REPLACE ALL OCCURRENCES OF '&lt;/&gt;' IN lv_line WITH '</b>'.
      REPLACE ALL OCCURRENCES OF PCRE '&lt;[A-Z0-9]{2,3}&gt;' IN lv_line WITH '<b>'.

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
                iv_maxuse TYPE i
                iv_falb   TYPE abap_bool
                iv_flang  TYPE sy-langu
                iv_calls  TYPE abap_bool
                iv_nosap  TYPE abap_bool
                iv_maxhit TYPE i
                iv_fsrc   TYPE abap_bool
                iv_udep   TYPE i.
    METHODS get_stat_packages RETURNING VALUE(rv) TYPE i.
    METHODS get_stat_objects  RETURNING VALUE(rv) TYPE i.
    METHODS get_stat_total    RETURNING VALUE(rv) TYPE i.
    METHODS get_stat_docu     RETURNING VALUE(rv) TYPE i.
    METHODS get_stat_source   RETURNING VALUE(rv) TYPE i.
    METHODS get_stat_usage    RETURNING VALUE(rv) TYPE i.
    METHODS get_stat_fallback RETURNING VALUE(rv) TYPE i.
    METHODS get_stat_calls    RETURNING VALUE(rv) TYPE i.
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
    METHODS source_lines
      IMPORTING iv_type          TYPE trobjtype
                iv_name          TYPE sobj_name
      RETURNING VALUE(rt_source) TYPE string_table.
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
    mv_calls  = iv_calls.
    mv_nosap  = iv_nosap.
    mv_maxhit = iv_maxhit.
    mv_fsrc   = iv_fsrc.
    mv_udep   = iv_udep.
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
      WHEN 'FUNC'. rv_title = lcl_t=>t( d = 'Funktionsbausteine' e = 'Function modules' ).
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
    DATA lv_i    TYPE i.

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

    rt_source = lt_src.

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
           END OF ty_use.
    DATA lt_use TYPE STANDARD TABLE OF ty_use.
    DATA ls_use TYPE ty_use.
    DATA lv_max TYPE i.

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

      SORT lt_use BY where.
      DELETE ADJACENT DUPLICATES FROM lt_use COMPARING where.

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
      WHERE pgmid = 'R3TR'
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
        FIND FIRST OCCURRENCE OF PCRE |\\b{ lv_tab }\\b| IN lv_code.
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
      FIND FIRST OCCURRENCE OF PCRE
        |^(?:INSERT\\s+(?:INTO\\s+)?\| \|UPDATE\\s+\| \|MODIFY\\s+\| \|DELETE\\s+(?:FROM\\s+)?)| &&
        |{ lv_tab }\\b|
        IN lv_up.
      IF sy-subrc = 0.
        lv_write = abap_true.
        CONTINUE.
      ENDIF.

      FIND FIRST OCCURRENCE OF PCRE |\\b(?:FROM\|JOIN)\\s+{ lv_tab }\\b|
        IN lv_up.
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
      WHEN 'C'.
*       A class and an interface share one input field, as in SE80. Which
*       of the two it is comes from the catalog.
        SELECT SINGLE object FROM tadir
          WHERE pgmid = 'R3TR' AND object IN ( 'CLAS', 'INTF' )
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
      WHERE pgmid = 'R3TR' AND obj_name = @it_name-table_line
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
      WHERE pgmid = 'R3TR'
        AND object IN ( 'CLAS', 'INTF', 'TABL', 'VIEW', 'DTEL', 'DOMA',
                        'TTYP', 'DDLS', 'PROG', 'FUGR', 'MSAG', 'SHLP',
                        'ENQU' )
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

      FIND FIRST OCCURRENCE OF PCRE `CALL\s+FUNCTION\s+'([A-Z0-9_/][^']*)'`
        IN lv_up SUBMATCHES lv_hit.
      IF sy-subrc = 0.
        APPEND CONV rs38l_fnam( lv_hit ) TO lt_fun.
      ENDIF.

      FIND FIRST OCCURRENCE OF PCRE `^SUBMIT\s+([A-Z0-9_/]+)`
        IN lv_up SUBMATCHES lv_hit.
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
      FIND ALL OCCURRENCES OF PCRE
        `\b(?:FROM|JOIN|UPDATE)\s+([A-Z][A-Z0-9_/]{2,29})\b`
        IN lv_up RESULTS DATA(lt_r1).
      LOOP AT lt_r1 INTO DATA(ls_r1).
        DATA(ls_sub1) = ls_r1-submatches[ 1 ].
        APPEND CONV sobj_name( lv_up+ls_sub1-offset(ls_sub1-length) ) TO lt_tab.
      ENDLOOP.

      FIND ALL OCCURRENCES OF PCRE
        `^(?:INSERT|MODIFY|DELETE)\s+([A-Z][A-Z0-9_/]{2,29})\s+FROM\b`
        IN lv_up RESULTS DATA(lt_r2).
      LOOP AT lt_r2 INTO DATA(ls_r2).
        DATA(ls_sub2) = ls_r2-submatches[ 1 ].
        APPEND CONV sobj_name( lv_up+ls_sub2-offset(ls_sub2-length) ) TO lt_tab.
      ENDLOOP.

*     Classes and interfaces: static access, a reference variable, or NEW.
      FIND ALL OCCURRENCES OF PCRE
        `\b([A-Z/][A-Z0-9_/]{2,29})\s*=>`
        IN lv_up RESULTS DATA(lt_r3).
      LOOP AT lt_r3 INTO DATA(ls_r3).
        DATA(ls_sub3) = ls_r3-submatches[ 1 ].
        APPEND CONV sobj_name( lv_up+ls_sub3-offset(ls_sub3-length) ) TO lt_cls.
      ENDLOOP.

      FIND ALL OCCURRENCES OF PCRE
        `\b(?:REF\s+TO|NEW)\s+([A-Z/][A-Z0-9_/]{2,29})\b`
        IN lv_up RESULTS DATA(lt_r4).
      LOOP AT lt_r4 INTO DATA(ls_r4).
        DATA(ls_sub4) = ls_r4-submatches[ 1 ].
        APPEND CONV sobj_name( lv_up+ls_sub4-offset(ls_sub4-length) ) TO lt_cls.
      ENDLOOP.

    ENDLOOP.

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
        WHERE pgmid = 'R3TR' AND object IN ( 'TABL', 'VIEW' )
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
        WHERE pgmid = 'R3TR' AND object IN ( 'CLAS', 'INTF' )
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
          WHERE pgmid = 'R3TR'
            AND object IN ( 'CLAS', 'INTF', 'TABL', 'VIEW', 'DTEL', 'DOMA',
                            'TTYP', 'DDLS', 'PROG', 'FUGR', 'MSAG', 'SHLP',
                            'ENQU' )
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
    IF iv_type = 'TABL' OR iv_type = 'VIEW'.
      DATA lv_tab TYPE dd03l-tabname.
      lv_tab = iv_name.
      SELECT DISTINCT rollname FROM dd03l
        WHERE tabname = @lv_tab AND as4local = 'A' AND rollname <> ''
        INTO TABLE @DATA(lt_rol)
        UP TO @lv_max ROWS.
      LOOP AT lt_rol INTO DATA(ls_rol).
        APPEND VALUE #( type = 'DTEL' name = ls_rol-rollname ) TO rt_ref.
      ENDLOOP.
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
      SELECT objectname FROM ddldependency
        WHERE ddlname = @lv_ddl2 AND state = 'A' AND objectname <> @lv_ddl2
        INTO TABLE @DATA(lt_dep)
        UP TO @lv_max ROWS.
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
        WHERE pgmid = 'R3TR' AND object = 'FUGR' AND obj_name = @lv_g
        INTO ( @lv_pack, @lv_auth ).
    ELSE.
      SELECT SINGLE devclass, author FROM tadir
        WHERE pgmid = 'R3TR' AND object = @iv_type AND obj_name = @iv_name
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

*   Only for the object the user asked about. The question "who uses this"
*   is about the entry point, not about its neighbourhood - a data element
*   like CHAR255 is used in thousands of SAP programs and would bury the
*   document under its own where-used list.
    IF mv_used = abap_true AND iv_root = abap_true.
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

  ENDMETHOD.

  METHOD collect_single.

*   Chapter 1 is the object the user asked for. Everything it refers to
*   follows in chapter 2, grouped by object type - the reader gets the
*   entry point first and the surroundings afterwards.
    DATA(ls_start) = start_object( ).

    mv_n_tot = 1.
    mv_n_obj = 1.
    DATA(lo_root) = document_object( iv_type  = ls_start-type
                                     iv_name  = ls_start-name
                                     iv_id    = `1`
                                     iv_level = 1
                                     iv_calls = abap_true
                                     iv_root  = abap_true ).
    co_document->add_chapter( lo_root ).

*   Breadth first, so that the direct neighbours of the start object are
*   documented before anything further out.
    DATA lt_queue TYPE ty_objrefs.
    DATA lt_done  TYPE ty_objrefs.
    DATA lt_open  TYPE ty_objrefs.
    DATA lv_depth TYPE i.

    APPEND VALUE #( type = ls_start-type name = ls_start-name ) TO lt_done.

    DATA(lo_refchap) = NEW lcl_chapter(
      iv_id    = `2`
      iv_level = 1
      iv_type  = 'GROUP'
      iv_title = lcl_t=>t( d = 'Verwendete Objekte'
                           e = 'Objects used' ) ).

    DATA lt_all TYPE ty_objrefs.

*   Die beiden Richtungen sind unabhaengig voneinander schaltbar: die
*   verwendeten Objekte haengen an "Ausgehende Aufrufe" und der
*   Verweistiefe, die verwendenden an "Verwendungsnachweis" und der
*   Verwendungstiefe.
    IF mv_calls = abap_true AND mv_rdep > 0.
      lt_queue = collect_refs( iv_type = ls_start-type iv_name = ls_start-name ).
    ENDIF.
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

      lt_uq = usage_objects( iv_type = ls_start-type
                             iv_name = ls_start-name ).
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
        lo_tchap = NEW lcl_chapter( iv_id    = |2.{ lv_tno }|
                                    iv_level = 2
                                    iv_type  = 'GROUP'
                                    iv_title = type_title( ls_a-type ) ).
        lo_refchap->add_child( lo_tchap ).
      ENDIF.

      lv_ono = lv_ono + 1.
      mv_n_obj = mv_n_obj + 1.

      lo_tchap->add_child( document_object( iv_type  = ls_a-type
                                            iv_name  = ls_a-name
                                            iv_id    = |2.{ lv_tno }.{ lv_ono }|
                                            iv_level = 3
                                            iv_calls = ls_a-deep ) ).

    ENDLOOP.

*   Kapitel 3: die verwendenden Objekte, gleiche Gliederung wie Kapitel 2.
    IF lt_users IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lo_usechap) = NEW lcl_chapter(
      iv_id    = `3`
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
        lo_tchap = NEW lcl_chapter( iv_id    = |3.{ lv_tno }|
                                    iv_level = 2
                                    iv_type  = 'GROUP'
                                    iv_title = type_title( ls_us-type ) ).
        lo_usechap->add_child( lo_tchap ).
      ENDIF.

      lv_ono = lv_ono + 1.
      mv_n_obj = mv_n_obj + 1.

      lo_tchap->add_child( document_object( iv_type  = ls_us-type
                                            iv_name  = ls_us-name
                                            iv_id    = |3.{ lv_tno }.{ lv_ono }|
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
        truncated  = lv_trunc
        node_limit = mv_maxobj
        node_total = mv_n_tot ) ).
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
      ( code = 'W'  text = 'CDS View' ) ).
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
      ( code = 'W'  text = 'CDS view' ) ).
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
           text TYPE char60,
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
                                              iv_maxuse = p_maxuse
                                              iv_falb   = p_falb
                                              iv_flang  = p_flang
                                              iv_calls  = p_calls
                                              iv_nosap  = p_nosap
                                              iv_maxhit = p_maxhit
                                              iv_fsrc   = p_fsrc
                                              iv_udep   = p_udep ).

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
