REPORT zdocumizer_img.

************************************************************************
* Documizer - Schritt 3: IMG-Collector ohne Dateninhalte
*
* Liest einen IMG-Strukturbaum, ordnet den Knoten die IMG-Aktivitaeten zu,
* uebernimmt die SAP-Standarddokumentation und gibt das Ergebnis als XML
* aus. Bewusst noch OHNE Customizing-Inhalte - das ist Schritt 4. Die
* zugeordneten Objekte werden mit Typ und Name aufgefuehrt, aber ohne
* Feldliste und ohne Daten.
*
* Enthaelt wie der Vorgaenger alles in einem Report, damit er per
* Copy/Paste in SE38 auf einem beliebigen System lauffaehig ist:
* Kapitelmodell, Schnittstellen, XML-Renderer und -Parser sind mit
* ZDOCUMIZER_CORE_DEMO identisch. Im Zielbild liegen sie als globale
* Klassen in ZCONS_DOCUMIZER_CORE; die Verdopplung ist der Preis fuer die
* Transportierbarkeit per Zwischenablage.
*
* Verwendete Standardschnittstellen:
*   STREE_HIERARCHY_READ  Struktur, Texte und Knotenverweise
*   DOCU_GET              Standarddokumentation, Dokuklasse HY
*   CUS_IMGACH            Kopfsatz der IMG-Aktivitaet
*   CUS_IMGACT            sprachabhaengiger Titel
*   CUS_ACTOBJ            zugeordnete Customizing-Objekte
*
* Der Knoten-Verweis steht in HIER_REF mit REF_TYPE = 'COBJ';
* REF_OBJECT ist die IMG-Aktivitaet.
************************************************************************

CLASS lcl_chapter  DEFINITION DEFERRED.
CLASS lcl_object   DEFINITION DEFERRED.
CLASS lcl_document DEFINITION DEFERRED.

*----------------------------------------------------------------------*
* Typen des Modells
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
  PRIVATE SECTION.
    DATA mv_id            TYPE string.
    DATA mv_level         TYPE i.
    DATA mv_type          TYPE string.
    DATA mv_title         TYPE string.
    DATA ms_reference     TYPE ty_reference.
    DATA mv_documentation TYPE string.
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
* Schnittstellen
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
      mo_writer->write_value( io_chapter->get_documentation( ) ).
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
              CLEAR: lv_otype, lv_oname, lv_otcod.
              LOOP AT lt_attr INTO lo_attr.
                CASE lo_attr->qname-name.
                  WHEN 'type'.  lv_otype = lo_attr->get_value( ).
                  WHEN 'name'.  lv_oname = lo_attr->get_value( ).
                  WHEN 'tcode'. lv_otcod = lo_attr->get_value( ).
                  WHEN 'filter'. DATA(lv_ofilt) = lo_attr->get_value( ).
                  WHEN 'note'.   DATA(lv_onote) = lo_attr->get_value( ).
                ENDCASE.
              ENDLOOP.
              lo_object = NEW lcl_object( iv_type  = lv_otype
                                          iv_name  = lv_oname
                                          iv_tcode = lv_otcod ).
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
*----------------------------------------------------------------------*
* Die Beschriftungen stehen bewusst im Quelltext und nicht im Textpool.
* Textelemente sind ein eigener Programmbestandteil, der beim Kopieren des
* Quelltextes in ein anderes System nicht mitkommt - dort stuenden sonst
* nur die technischen Feldnamen. Ueber COMMENT-Felder, die in
* INITIALIZATION gefuellt werden, ist der Report ohne Nacharbeit lesbar.

* Die Felder gv_* werden von SELECTION-SCREEN COMMENT bzw. FRAME TITLE
* implizit angelegt und duerfen nicht zusaetzlich per DATA deklariert
* werden - sonst meldet der Compiler eine Doppeldeklaration.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE gv_blk1.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_ttree FOR FIELD p_tree.
    PARAMETERS p_tree TYPE ttree-id.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tsrch FOR FIELD p_srch.
    PARAMETERS p_srch TYPE tnodeimgt-text.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE gv_blk2.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tlang FOR FIELD p_langu.
    PARAMETERS p_langu TYPE sy-langu DEFAULT sy-langu.
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
    SELECTION-SCREEN COMMENT 1(30) gv_tdown FOR FIELD p_down.
    PARAMETERS p_down AS CHECKBOX.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_tpath FOR FIELD p_path.
    PARAMETERS p_path TYPE char128 LOWER CASE DEFAULT 'C:\temp'.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK b3.

INITIALIZATION.
  gv_blk1   = 'Auswahl der Struktur'.
  gv_blk2   = 'Umfang'.
  gv_blk3   = 'Ausgabe'.
  gv_ttree  = 'Struktur-ID (GUID)'.
  gv_tsrch  = 'oder Suchbegriff Wurzel'.
  gv_tlang = 'Sprache'.
  gv_tdep = 'Max. Tiefe (0 = alle)'.
  gv_tmaxn  = 'Max. Kapitel (0 = alle)'.
  gv_tsubs  = 'Unterstrukturen auflösen'.
  gv_tdoku  = 'Standarddokumentation'.
  gv_tobj   = 'Objektzuordnung'.
  gv_tdata  = 'Customizing-Inhalte lesen'.
  gv_tcust  = 'nur kundeneigene Einträge'.
  gv_tmaxr  = 'Max. Zeilen (0 = alle)'.
  gv_thist  = 'Transport-Historie'.
  gv_txml   = 'XML erzeugen/ausgeben'.
  gv_thtml  = 'HTML erzeugen/anzeigen'.
  gv_trt    = 'Roundtrip prüfen'.
  gv_tdown  = 'Download auf PC'.
  gv_tpath  = 'Zielverzeichnis'.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_path.
  PERFORM f4_verzeichnis.

* Wertehilfe fuer die Struktur-ID. Die DDIC-Suchhilfe auf TTREE-ID liefert
* nur nackte GUIDs ohne Bezeichnung und ist damit unbrauchbar. Hier werden
* stattdessen die Wurzelknoten mit ihrem Text angeboten, optional gefiltert
* ueber den Suchbegriff im zweiten Feld.
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_tree.
  PERFORM f4_struktur.

*----------------------------------------------------------------------*
* lcl_cust - Auflösung und Lesen des Customizings (Schritt 4)
*
* Views und View-Cluster werden immer auf ihre Basistabellen aufgelöst.
* Ein Pflegeview lässt sich nicht per SELECT lesen, ein Datenbankview
* schon - die Unterscheidung entfällt, wenn grundsätzlich aus den
* transparenten Tabellen gelesen wird.
*
* "Kundeneigen" wird über zwei Verfahren zugleich bestimmt:
*   Namensraum   erstes Schlüsselfeld beginnt mit Y, Z oder /
*   Transport    Schlüssel taucht in E071K zu dieser Tabelle auf
* Beides greift per ODER. Der Namensraum findet auch nie transportiertes
* Customizing, der Transportweg auch Schlüssel ausserhalb des
* Kundennamensraums. Welches Verfahren gegriffen hat, steht am Objekt.
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

    " Lage des ersten fachlichen Schlüsselfeldes im TABKEY bestimmen
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
      io_obj->set_note( |{ io_obj->get_note( ) } Keine Leseberechtigung (S_TABU_NAM).| ).
      io_obj->set_filter( 'GESPERRT' ).
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
        io_obj->set_filter( 'ALLE' ).
        io_obj->set_note( |{ io_obj->get_note( ) } Kundenfilter nicht anwendbar.| ).
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
            io_obj->set_filter( 'NAMENSRAUM+TRANSPORT' ).
          ELSE.
            io_obj->set_filter( 'NAMENSRAUM' ).
          ENDIF.
        ELSE.
          io_obj->set_filter( 'NAMENSRAUM' ).
        ENDIF.
      ENDIF.

    ELSE.
      io_obj->set_filter( 'ALLE' ).
    ENDIF.

    TRY.
        SELECT COUNT(*) FROM (iv_tab) WHERE (lt_where) INTO @lv_cnt.
      CATCH cx_root.
        io_obj->set_note( |{ io_obj->get_note( ) } Tabelle nicht lesbar.| ).
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
        io_obj->set_note( |{ io_obj->get_note( ) } Daten nicht lesbar.| ).
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
      lo_none->set_note( 'Kein lesbares Datenobjekt hinterlegt.' ).
      APPEND lo_none TO rt_objects.
      RETURN.
    ENDIF.

    LOOP AT lt_names INTO DATA(lv_tab).

      DATA(lo_obj) = NEW lcl_object( iv_type  = iv_type
                                     iv_name  = lv_tab
                                     iv_tcode = iv_tcode ).

      IF lv_tab <> iv_name.
        lo_obj->set_note( |Basistabelle aus { iv_name }.| ).
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
* lcl_collector_img - der eigentliche Gegenstand von Schritt 3
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
                io_cust    TYPE REF TO lcl_cust OPTIONAL.
    METHODS get_stat_nodes      RETURNING VALUE(rv) TYPE i.
    METHODS get_stat_activities RETURNING VALUE(rv) TYPE i.
    METHODS get_stat_docu       RETURNING VALUE(rv) TYPE i.
    METHODS get_stat_objects    RETURNING VALUE(rv) TYPE i.
  PRIVATE SECTION.
    DATA mv_tree_id TYPE ttree-id.
    DATA mv_langu   TYPE sy-langu.
    DATA mv_depth   TYPE i.
    DATA mv_maxnod  TYPE i.
    DATA mv_subs    TYPE abap_bool.
    DATA mv_doku    TYPE abap_bool.
    DATA mv_obj     TYPE abap_bool.
    DATA mo_cust    TYPE REF TO lcl_cust.
    DATA mv_n_nodes TYPE i.
    DATA mv_n_total TYPE i.
    DATA mv_n_act   TYPE i.
    DATA mv_n_docu  TYPE i.
    DATA mv_n_obj   TYPE i.
    METHODS enrich_activity
      IMPORTING io_chapter  TYPE REF TO lcl_chapter
                iv_activity TYPE string.
    METHODS read_documentation
      IMPORTING iv_docu_id     TYPE string
      RETURNING VALUE(rv_text) TYPE string.
ENDCLASS.

CLASS lcl_collector_img IMPLEMENTATION.

  METHOD constructor.
    mv_tree_id = iv_tree_id.
    mv_langu   = iv_langu.
    mv_depth   = iv_depth.
    mv_maxnod  = iv_maxnod.
    mv_subs    = iv_subs.
    mo_cust    = io_cust.
    mv_doku    = iv_doku.
    mv_obj     = iv_obj.
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

    " Struktur, Texte und Knotenverweise lesen.
    "
    " Wichtig: STREE_HIERARCHY_READ liefert nur die eigene Struktur. Im IMG
    " sind die Unterkapitel jedoch REF-Knoten auf eigenstaendige Strukturen -
    " ein Lauf ohne Aufloesung endet daher nach der ersten Ebene und findet
    " keine einzige Aktivitaet. STREE_HIERARCHY_READ_ALL_SUBS loest die
    " Verweise auf und liefert den durchgaengigen Baum.
    IF mv_subs = abap_true.
      CALL FUNCTION 'STREE_HIERARCHY_READ_ALL_SUBS'
        EXPORTING
          struct_id  = mv_tree_id
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
          structure_id       = mv_tree_id
          language           = mv_langu
          read_also_texts    = abap_true
        IMPORTING
          message            = ls_msg
        TABLES
          list_of_nodes      = lt_nodes
          list_of_texts      = lt_texts
          list_of_references = lt_refs.
    ENDIF.

    " Verweise und Texte fuer den Direktzugriff aufbereiten.
    DATA lt_ref_idx TYPE HASHED TABLE OF hier_ref
                    WITH UNIQUE KEY node_id ref_type.
    LOOP AT lt_refs INTO DATA(ls_ref_line).
      IF ls_ref_line-ref_type = gc_reftype AND ls_ref_line-del_flag IS INITIAL.
        INSERT ls_ref_line INTO TABLE lt_ref_idx.
      ENDIF.
    ENDLOOP.

    SORT lt_texts BY node_id.

    DATA lv_level TYPE i.

    LOOP AT lt_nodes INTO DATA(ls_node).

      lv_level = ls_node-node_level.

      IF mv_depth > 0 AND lv_level > mv_depth.
        CONTINUE.
      ENDIF.

      " Alle Knoten zaehlen, die in den Umfang fielen - auch die, die das
      " Limit abschneidet. Nur so laesst sich im Dokument angeben, wie
      " vollstaendig es ist.
      mv_n_total = mv_n_total + 1.

      IF mv_maxnod > 0 AND mv_n_nodes >= mv_maxnod.
        lv_trunc = abap_true.
        CONTINUE.
      ENDIF.

      " Stapel auf die Elternebene zurueckschneiden
      WHILE lines( lt_stack ) >= lv_level.
        DELETE lt_stack INDEX lines( lt_stack ).
      ENDWHILE.

      " Kapitelnummer fortschreiben
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

      " Titel
      DATA lv_title TYPE string.
      CLEAR lv_title.
      READ TABLE lt_texts INTO DATA(ls_text)
           WITH KEY node_id = ls_node-node_id BINARY SEARCH.
      IF sy-subrc = 0.
        lv_title = ls_text-text.
      ENDIF.

      " Aktivitaet oder Gliederung?
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

      mv_n_nodes = mv_n_nodes + 1.

      IF lv_act IS NOT INITIAL.
        mv_n_act = mv_n_act + 1.
        enrich_activity( io_chapter = lo_chapter iv_activity = lv_act ).
      ENDIF.

    ENDLOOP.

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

    " Sprachabhaengiger Titel der Aktivitaet, falls der Knotentext leer ist
    IF io_chapter->get_title( ) IS INITIAL.
      SELECT SINGLE text FROM cus_imgact
        WHERE spras = @mv_langu AND activity = @lv_act
        INTO @DATA(lv_text).
      IF sy-subrc = 0.
        io_chapter->set_title( CONV string( lv_text ) ).
      ENDIF.
    ENDIF.

    " SAP-Standarddokumentation, Dokuklasse HY
    IF mv_doku = abap_true AND ls_reference-docu_id IS NOT INITIAL.
      DATA(lv_docu) = read_documentation( ls_reference-docu_id ).
      IF lv_docu IS NOT INITIAL.
        io_chapter->set_documentation( lv_docu ).
        mv_n_docu = mv_n_docu + 1.
      ENDIF.
    ENDIF.

    " Zugeordnete Customizing-Objekte - Schritt 3 bewusst ohne Inhalte
    IF mv_obj = abap_true.
      DATA lv_actid TYPE cus_actobj-act_id.
      lv_actid = iv_activity.
      SELECT objecttype, objectname, tcode
        FROM cus_actobj
        WHERE act_id = @lv_actid
        INTO TABLE @DATA(lt_obj).
      LOOP AT lt_obj INTO DATA(ls_obj).
        IF mo_cust IS BOUND.
          " Schritt 4: Objekt auflösen und Inhalte lesen
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

  ENDMETHOD.

  METHOD read_documentation.

    DATA lt_line TYPE STANDARD TABLE OF tline.
    DATA lv_obj  TYPE dokhl-object.

    lv_obj = iv_docu_id.

    CALL FUNCTION 'DOCU_GET'
      EXPORTING
        id                = gc_docuclas
        langu             = mv_langu
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

    " Die ITF-Formatkennzeichen werden hier noch nicht ausgewertet; die
    " Zeilen werden nur zusammengefuehrt. Die Umsetzung nach HTML bzw.
    " Markdown gehoert zu Schritt 6.
    LOOP AT lt_line INTO DATA(ls_line).
      IF rv_text IS INITIAL.
        rv_text = ls_line-tdline.
      ELSE.
        rv_text = |{ rv_text }{ cl_abap_char_utilities=>newline }{ ls_line-tdline }|.
      ENDIF.
    ENDLOOP.

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
* lcl_renderer_html - lesbare Ausgabe aus demselben Kapitelmodell
*
* Bewusst eine in sich geschlossene Datei ohne externe Abhaengigkeiten:
* CSS eingebettet, kein JavaScript. Die Datei soll auch in Jahren noch
* ohne Nacharbeit zu oeffnen sein.
*
* Die ITF-Formatkennzeichen der Dokumentation werden noch nicht
* ausgewertet, der Text erscheint als vorformatierter Block. Die
* Umsetzung nach Absaetzen und Listen gehoert zu Schritt 6.
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
    METHODS itf_to_html   IMPORTING iv_text TYPE string
                          RETURNING VALUE(rv_html) TYPE string.
    METHODS itf_section   IMPORTING iv_marker TYPE string
                          RETURNING VALUE(rv_label) TYPE string.
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

  METHOD itf_section.
    " Die IMG-Dokumentation ist in feste Abschnitte gegliedert, die im
    " ITF-Text als &NAME& stehen. Sie werden zu Zwischenüberschriften.
    CASE iv_marker.
      WHEN 'SHORTTEXT'.      rv_label = 'Kurztext'.
      WHEN 'USE'.            rv_label = 'Verwendung'.
      WHEN 'PRECONDITIONS'.  rv_label = 'Voraussetzungen'.
      WHEN 'STANDARD_SETUP'. rv_label = 'Standardeinstellungen'.
      WHEN 'ACTIVITY'.       rv_label = 'Vorgehen'.
      WHEN 'EXAMPLE'.        rv_label = 'Beispiel'.
      WHEN 'RECOMMENDATION'. rv_label = 'Empfehlung'.
      WHEN 'CAUTION'.        rv_label = 'Achtung'.
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

      " SAPscript-Steueranweisung, kein Inhalt
      IF lv_line = 'RESET N1'.
        CONTINUE.
      ENDIF.

      IF lv_line IS INITIAL.
        rv_html = |{ rv_html }<p></p>|.
        CONTINUE.
      ENDIF.

      " Abschnittsmarke &NAME& - wird zur Überschrift, die Kaufmanns-Und
      " verschwinden dabei.
      "
      " Die Pruefung laeuft ueber einen regulaeren Ausdruck und nicht ueber
      " CS: der Vergleichsoperator ignoriert nachgestellte Leerzeichen im
      " Suchbegriff, weshalb "zeile CS space" immer wahr ist.
      lv_len = strlen( lv_line ).
      FIND PCRE '^&[A-Z0-9_]+&$' IN lv_line.
      IF sy-subrc = 0.
        rv_html = |{ rv_html }<p class="sec">{ esc(
                    itf_section( substring( val = lv_line off = 1 len = lv_len - 2 ) ) ) }</p>|.
        CONTINUE.
      ENDIF.

      lv_line = esc( lv_line ).

      " ITF-Auszeichnungen: Verweise und Hervorhebungen werden fett
      " dargestellt, die schliessende Marke gilt fuer alle drei.
      REPLACE ALL OCCURRENCES OF PCRE '&lt;DS:[^&]+&gt;' IN lv_line WITH '<b>'.
      REPLACE ALL OCCURRENCES OF '&lt;ZH&gt;' IN lv_line WITH '<b>'.
      REPLACE ALL OCCURRENCES OF '&lt;LS&gt;' IN lv_line WITH '<b>'.
      REPLACE ALL OCCURRENCES OF '&lt;/&gt;'  IN lv_line WITH '</b>'.

      " Tabulatoren der ITF-Ablage
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
    add( 'div.doc p{margin:0 0 6px 0}' ).
    add( '.ref{color:#666;font-size:11px;margin:2px 0}' ).
    add( '.warn{color:#a00;font-weight:bold}' ).
    add( 'ul.toc{line-height:1.6}' ).
    add( '</style></head><body>' ).

    add( |<h1>Documizer - { esc( ls_meta-doc_type ) }-Dokumentation</h1>| ).

    add( '<table>' ).
    add( |<tr><th>System</th><td>{ esc( ls_meta-system ) }| &&
         | / Mandant { esc( ls_meta-client ) }</td></tr>| ).
    add( |<tr><th>Erzeugt</th><td>{ esc( ls_meta-created_at ) }| &&
         | von { esc( ls_meta-created_by ) }</td></tr>| ).
    add( |<tr><th>Sprache</th><td>{ esc( ls_meta-language ) }</td></tr>| ).
    add( |<tr><th>Format</th><td>Version { esc( ls_meta-version ) }</td></tr>| ).

    DATA lv_limit TYPE string.
    IF ls_meta-node_limit = 0.
      lv_limit = 'ohne Begrenzung'.
    ELSE.
      lv_limit = |Limit { ls_meta-node_limit }|.
    ENDIF.
    add( |<tr><th>Kapitel</th><td>{ ls_meta-node_total } im gewählten Umfang, | &&
         |{ lv_limit }</td></tr>| ).
    add( '</table>' ).

    IF ls_meta-truncated = abap_true.
      add( |<p class="warn">Achtung: Von { ls_meta-node_total } Kapiteln im | &&
           |gewählten Umfang sind nur { ls_meta-node_limit } enthalten. | &&
           |Das Dokument ist unvollständig.</p>| ).
    ENDIF.

    add( '<h2>Inhalt</h2><ul class="toc">' ).
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
    " Nur die obersten beiden Ebenen, sonst wird das Verzeichnis laenger
    " als das Dokument.
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
      add( |<p class="ref">IMG-Aktivität { esc( ls_ref-activity ) }| &&
           |, Transaktion { esc( ls_ref-tcode ) }| &&
           |, Dokuobjekt { esc( ls_ref-docu_id ) }</p>| ).
    ENDIF.

    IF io_chapter->get_documentation( ) IS NOT INITIAL.
      add( itf_to_html( io_chapter->get_documentation( ) ) ).
    ENDIF.

    LOOP AT io_chapter->get_objects( ) INTO DATA(lo_obj).

      DATA lv_rows TYPE string.
      IF lo_obj->get_truncated( ) = abap_true.
        lv_rows = |{ lines( lo_obj->get_rows( ) ) } von { lo_obj->get_row_count( ) } (gekürzt)|.
      ELSE.
        lv_rows = |{ lo_obj->get_row_count( ) }|.
      ENDIF.

      add( |<p class="obj"><b>{ esc( lo_obj->get_name( ) ) }</b>| &&
           | &nbsp; Typ { esc( lo_obj->get_type( ) ) }| &&
           | &nbsp; Transaktion { esc( lo_obj->get_tcode( ) ) }| &&
           | &nbsp; Zeilen { lv_rows }| &&
           | &nbsp; Auswahl { esc( lo_obj->get_filter( ) ) }</p>| ).

      IF lo_obj->get_note( ) IS NOT INITIAL.
        add( |<p class="warn">{ esc( lo_obj->get_note( ) ) }</p>| ).
      ENDIF.

      " Dateninhalte
      IF lines( lo_obj->get_rows( ) ) > 0.
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
      ELSEIF lines( lo_obj->get_fields( ) ) > 0.
        " keine Daten, aber Struktur bekannt
        add( '<table><tr><th>Feld</th><th>Datenelement</th><th>Schlüssel</th></tr>' ).
        LOOP AT lo_obj->get_fields( ) INTO DATA(ls_fs).
          add( |<tr><td>{ esc( ls_fs-name ) }</td>| &&
               |<td>{ esc( ls_fs-rollname ) }</td>| &&
               |<td>{ COND string( WHEN ls_fs-keyflag = abap_true THEN 'X' ELSE '' ) }</td></tr>| ).
        ENDLOOP.
        add( '</table>' ).
      ENDIF.

      " Transport-Historie
      IF lines( lo_obj->get_transports( ) ) > 0.
        add( '<p class="ref">Transport-Historie</p>' ).
        add( '<table><tr><th>Auftrag</th><th>Benutzer</th>' &&
             '<th>Datum</th><th>Kurztext</th></tr>' ).
        LOOP AT lo_obj->get_transports( ) INTO DATA(ls_th).
          add( |<tr><td>{ esc( ls_th-trkorr ) }</td>| &&
               |<td>{ esc( ls_th-user ) }</td>| &&
               |<td>{ esc( ls_th-date ) }</td>| &&
               |<td>{ esc( ls_th-text ) }</td></tr>| ).
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
* Wertehilfe fuer die Struktur-ID
*----------------------------------------------------------------------*
FORM f4_struktur.

* Die Spalten tragen bewusst DDIC-Typen: die Wertehilfe leitet ihre
* Ueberschriften daraus ab. Die Knotenzahl haengt am Text, weil es dafuer
* kein Datenelement mit brauchbarer Bezeichnung gibt - und sie ist der
* wichtigste Unterscheider, wenn mehrere Strukturen gleich heissen.

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

  " Strukturtyp und Aenderungsdatum
  SELECT id, type, ldate FROM ttree
    WHERE id IN @lr_tree
    INTO TABLE @DATA(lt_tree).

  " Knotenzahl je Struktur - ohne FOR ALL ENTRIES, weil Aggregate damit
  " nicht zulaessig sind
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
* Wertehilfe fuer das Zielverzeichnis
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
* Datei auf den PC schreiben
*
* Der Inhalt wird zuerst nach UTF-8 gewandelt und binaer geschrieben.
* Ein Textdownload wuerde die Zeichen in die Frontend-Codepage umsetzen,
* und genau dort gehen Umlaute und Sonderzeichen verloren.
*----------------------------------------------------------------------*
FORM download USING iv_content TYPE string
                    iv_ext     TYPE string.

  DATA lv_x    TYPE xstring.
  DATA lv_len  TYPE i.
  DATA lt_bin  TYPE solix_tab.
  DATA lv_file TYPE string.
  DATA lv_dir  TYPE string.

  IF sy-batch = abap_true.
    WRITE: / 'Download im Hintergrund nicht möglich:', iv_ext.
    RETURN.
  ENDIF.

  lv_dir = p_path.
  SHIFT lv_dir RIGHT DELETING TRAILING space.
  SHIFT lv_dir LEFT  DELETING LEADING space.
  IF lv_dir CA '\'.
    " Verzeichnis ohne abschliessenden Trenner ergaenzen
    IF substring( val = lv_dir off = strlen( lv_dir ) - 1 len = 1 ) <> '\'.
      lv_dir = |{ lv_dir }\\|.
    ENDIF.
  ENDIF.

  lv_file = |{ lv_dir }documizer_{ sy-sysid }_{ sy-datum }_{ sy-uzeit }.{ iv_ext }|.

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
    WRITE: / 'Datei geschrieben               :', lv_file.
  ELSE.
    WRITE: / 'Download fehlgeschlagen         :', lv_file.
  ENDIF.

ENDFORM.

*----------------------------------------------------------------------*
* Hilfsroutine: Strukturen suchen, wenn keine GUID bekannt ist
*----------------------------------------------------------------------*
FORM search_structures.

  DATA lv_pattern TYPE string.

  IF p_srch IS INITIAL.
    WRITE: / 'Bitte Struktur-GUID (P_TREE) oder Suchbegriff (P_SRCH) angeben.'.
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
    WRITE: / 'Keine IMG-Struktur gefunden zu:', p_srch.
    RETURN.
  ENDIF.

  WRITE: / 'Gefundene IMG-Strukturen - GUID in P_TREE übernehmen'.
  ULINE.
  LOOP AT lt_hits INTO DATA(ls_hit).
    WRITE: / ls_hit-tree_id, ls_hit-text.
  ENDLOOP.

ENDFORM.

*----------------------------------------------------------------------*
* Ablauf
*----------------------------------------------------------------------*
START-OF-SELECTION.

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

* XML wird nur erzeugt, wenn es auch gebraucht wird: fuer die Ausgabe,
* fuer den Download oder fuer den Roundtrip-Selbsttest.
  DATA lv_xml TYPE string.
  IF p_xml = abap_true OR p_rtest = abap_true
     OR ( p_down = abap_true AND p_xml = abap_true ).
    lv_xml = lo_renderer->render( lo_doc ).
  ENDIF.

  WRITE: / 'Documizer - IMG-Collector (ohne Dateninhalte)'.
  ULINE.
  WRITE: / 'Struktur                         :', p_tree.
  DATA(ls_docmeta) = lo_doc->get_meta( ).

  WRITE: / 'Kapitel erzeugt                  :', lo_collector->get_stat_nodes( ).
  WRITE: / 'Kapitel im gewaehlten Umfang     :', ls_docmeta-node_total.
  IF p_maxnod = 0.
    WRITE: / 'Limit                            : ohne Begrenzung'.
  ELSE.
    WRITE: / 'Limit                            :', p_maxnod.
  ENDIF.
  WRITE: / 'davon Aktivitäten                :', lo_collector->get_stat_activities( ).
  WRITE: / 'mit Standarddokumentation        :', lo_collector->get_stat_docu( ).
  WRITE: / 'zugeordnete Objekte              :', lo_collector->get_stat_objects( ).
  IF lv_xml IS NOT INITIAL.
    WRITE: / 'XML-Zeichen                      :', strlen( lv_xml ).
  ENDIF.

  IF ls_docmeta-truncated = abap_true.
    WRITE: / 'ACHTUNG: Limit erreicht, Dokument unvollständig.'.
  ENDIF.

  " Roundtrip gegen echte Daten pruefen, nicht nur gegen ein Beispiel
  IF p_rtest = abap_true.
    DATA(lo_doc2) = lcl_parser_xml=>parse( lv_xml ).
    DATA(lv_xml2) = lo_renderer->render( lo_doc2 ).
    IF lv_xml = lv_xml2.
      WRITE: / 'Roundtrip                        : IDENTISCH - bestanden'.
    ELSE.
      WRITE: / 'Roundtrip                        : ABWEICHUNG', strlen( lv_xml2 ).
    ENDIF.
  ENDIF.

  IF p_down = abap_true AND p_xml = abap_true.
    PERFORM download USING lv_xml 'xml'.
  ENDIF.

  IF p_html = abap_true.
    DATA lo_html TYPE REF TO lif_docu_renderer.
    lo_html = NEW lcl_renderer_html( ).
    DATA(lv_html) = lo_html->render( lo_doc ).
    WRITE: / 'HTML-Zeichen                     :', strlen( lv_html ).

    IF p_down = abap_true.
      PERFORM download USING lv_html 'html'.
    ENDIF.

    IF sy-batch = abap_false.
      cl_abap_browser=>show_html( html_string = lv_html
                                  title       = 'Documizer' ).
    ELSE.
      WRITE: / 'HTML-Anzeige im Hintergrund nicht möglich.'.
    ENDIF.
  ENDIF.

  IF p_xml = abap_true.
    SKIP.
    WRITE: / 'Erzeugtes XML'.
    ULINE.
    DATA(lv_pretty) = lo_renderer->render( io_document = lo_doc iv_pretty = abap_true ).
    SPLIT lv_pretty AT cl_abap_char_utilities=>newline INTO TABLE DATA(lt_lines).
    LOOP AT lt_lines INTO DATA(lv_line).
      WRITE: / lv_line.
    ENDLOOP.
  ENDIF.
