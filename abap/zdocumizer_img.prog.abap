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
  PRIVATE SECTION.
    DATA mv_type      TYPE string.
    DATA mv_name      TYPE string.
    DATA mv_tcode     TYPE string.
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
    mo_writer->write_attribute( name = 'tcode' value = io_object->get_tcode( ) ).

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
              OR 'language' OR 'truncated'.
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
                ENDCASE.
              ENDLOOP.
              lo_object = NEW lcl_object( iv_type  = lv_otype
                                          iv_name  = lv_oname
                                          iv_tcode = lv_otcod ).
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
SELECTION-SCREEN END OF BLOCK b2.

SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE gv_blk3.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_txml FOR FIELD p_xml.
    PARAMETERS p_xml AS CHECKBOX DEFAULT 'X'.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_trt FOR FIELD p_rtest.
    PARAMETERS p_rtest AS CHECKBOX DEFAULT 'X'.
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
  gv_tsubs  = 'Unterstrukturen aufloesen'.
  gv_tdoku  = 'Standarddokumentation'.
  gv_tobj   = 'Objektzuordnung'.
  gv_txml   = 'XML ausgeben'.
  gv_trt = 'Roundtrip pruefen'.

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
                iv_obj     TYPE abap_bool.
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
    DATA mv_n_nodes TYPE i.
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

      IF mv_maxnod > 0 AND mv_n_nodes >= mv_maxnod.
        lv_trunc = abap_true.
        EXIT.
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
      truncated  = lv_trunc ) ).

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
        io_chapter->add_object( NEW lcl_object(
          iv_type  = CONV string( ls_obj-objecttype )
          iv_name  = CONV string( ls_obj-objectname )
          iv_tcode = CONV string( ls_obj-tcode ) ) ).
        mv_n_obj = mv_n_obj + 1.
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

  WRITE: / 'Gefundene IMG-Strukturen - GUID in P_TREE uebernehmen'.
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
                                              iv_obj     = p_obj ).

  DATA lo_coll TYPE REF TO lif_docu_collector.
  lo_coll = lo_collector.

  DATA(lo_doc) = lo_coll->collect( ).

  DATA lo_renderer TYPE REF TO lif_docu_renderer.
  lo_renderer = NEW lcl_renderer_xml( ).

  DATA(lv_xml) = lo_renderer->render( lo_doc ).

  WRITE: / 'Documizer - IMG-Collector (ohne Dateninhalte)'.
  ULINE.
  WRITE: / 'Struktur                         :', p_tree.
  WRITE: / 'Kapitel gesamt                   :', lo_collector->get_stat_nodes( ).
  WRITE: / 'davon Aktivitaeten               :', lo_collector->get_stat_activities( ).
  WRITE: / 'mit Standarddokumentation        :', lo_collector->get_stat_docu( ).
  WRITE: / 'zugeordnete Objekte              :', lo_collector->get_stat_objects( ).
  WRITE: / 'XML-Zeichen                      :', strlen( lv_xml ).

  IF lo_doc->get_meta( )-truncated = abap_true.
    WRITE: / 'ACHTUNG: Knotengrenze erreicht, Baum unvollstaendig.'.
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
