REPORT zdocumizer_core_demo.

************************************************************************
* consiness Documizer - Kernmodell und Selbsttest
*
* Enthaelt vollstaendig in einem Report, damit er per Copy/Paste in SE38
* auf einem beliebigen System lauffaehig ist:
*
*   - das generische Kapitelmodell   lcl_chapter, lcl_object, lcl_document
*   - die beiden Schnittstellen      lif_docu_collector, lif_docu_renderer
*   - XML-Renderer und XML-Parser    auf Basis sXML
*   - einen Demo-Collector           kleines IMG-Beispiel
*   - den Roundtrip-Nachweis         Modell -> XML -> Modell -> XML
*
* Bewusste Abweichung von der Spezifikation: dort ist eine Simple
* Transformation vorgesehen. Eine ST ist ein eigenes Repository-Objekt und
* laesst sich nicht in einen kopierbaren Report packen. Stattdessen wird
* sXML verwendet (cl_sxml_string_writer / cl_sxml_string_reader). Das
* erzeugte XML-Format ist identisch zu dem in der Spezifikation
* beschriebenen. Beim Umzug in das Paket ZCONS_DOCUMIZER_CORE kann die ST
* nachgezogen werden - noetig ist sie nicht.
*
* Der Roundtrip wird nicht behauptet, sondern gemessen: das Modell wird
* serialisiert, aus dem XML neu aufgebaut und erneut serialisiert. Beide
* XML-Strings muessen zeichengleich sein.
*
* Copyright 2026 consiness GmbH
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
       END OF ty_meta.

TYPES ty_chapters TYPE STANDARD TABLE OF REF TO lcl_chapter WITH EMPTY KEY.
TYPES ty_objects  TYPE STANDARD TABLE OF REF TO lcl_object  WITH EMPTY KEY.

CONSTANTS gc_version TYPE string VALUE '1.0'.

*----------------------------------------------------------------------*
* lcl_object - Datenobjekt innerhalb eines Kapitels
*
* Traegt Struktur und Inhalt eines Customizing-Objekts bzw. eines
* Entwicklungsobjekts. row_count und truncated sind bewusst getrennt:
* row_count ist die Gesamtzahl im System, die Zeilentabelle kann durch
* die Mengenbegrenzung kuerzer sein. Ein Dokument darf nie unbemerkt
* unvollstaendig sein.
*----------------------------------------------------------------------*
CLASS lcl_object DEFINITION.
  PUBLIC SECTION.
    METHODS constructor
      IMPORTING iv_type TYPE string
                iv_name TYPE string.
    METHODS add_field     IMPORTING is_field     TYPE ty_field.
    METHODS add_row       IMPORTING is_row       TYPE ty_row.
    METHODS set_row_count IMPORTING iv_row_count TYPE i.
    METHODS set_truncated IMPORTING iv_truncated TYPE abap_bool.
    METHODS get_type      RETURNING VALUE(rv_type)      TYPE string.
    METHODS get_name      RETURNING VALUE(rv_name)      TYPE string.
    METHODS get_fields    RETURNING VALUE(rt_fields)    TYPE ty_fields.
    METHODS get_rows      RETURNING VALUE(rt_rows)      TYPE ty_rows.
    METHODS get_row_count RETURNING VALUE(rv_row_count) TYPE i.
    METHODS get_truncated RETURNING VALUE(rv_truncated) TYPE abap_bool.
  PRIVATE SECTION.
    DATA mv_type      TYPE string.
    DATA mv_name      TYPE string.
    DATA mt_fields    TYPE ty_fields.
    DATA mt_rows      TYPE ty_rows.
    DATA mv_row_count TYPE i.
    DATA mv_truncated TYPE abap_bool.
ENDCLASS.

CLASS lcl_object IMPLEMENTATION.
  METHOD constructor.
    mv_type = iv_type.
    mv_name = iv_name.
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
* lcl_chapter - Kapitelknoten
*
* Ein Knoten ist entweder Gliederungskapitel (type STRUCTURE) oder
* Inhaltskapitel (type ACTIVITY bzw. OBJECT). Die Unterscheidung faellt
* im Collector, nicht im Modell - das Modell bleibt fuer IMG und
* Development identisch.
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
    METHODS get_id            RETURNING VALUE(rv_id)      TYPE string.
    METHODS get_level         RETURNING VALUE(rv_level)   TYPE i.
    METHODS get_type          RETURNING VALUE(rv_type)    TYPE string.
    METHODS get_title         RETURNING VALUE(rv_title)   TYPE string.
    METHODS get_children      RETURNING VALUE(rt_children) TYPE ty_chapters.
    METHODS get_objects       RETURNING VALUE(rt_objects)  TYPE ty_objects.
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
* lcl_document - Klammer aus Metadaten und Kapitelbaum
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
*
* Beide Reports - IMG und Development - unterscheiden sich nur in der
* Collector-Implementierung. Renderer und Modell sind gemeinsam.
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
* lcl_renderer_xml - Serialisierung
*----------------------------------------------------------------------*
CLASS lcl_renderer_xml DEFINITION.
  PUBLIC SECTION.
    INTERFACES lif_docu_renderer.
  PRIVATE SECTION.
    DATA mo_writer TYPE REF TO if_sxml_writer.
    METHODS write_text_element
      IMPORTING iv_name  TYPE string
                iv_value TYPE string.
    METHODS write_chapter
      IMPORTING io_chapter TYPE REF TO lcl_chapter.
    METHODS write_object
      IMPORTING io_object TYPE REF TO lcl_object.
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
    mo_writer->write_attribute( name = 'type' value = io_object->get_type( ) ).
    mo_writer->write_attribute( name = 'name' value = io_object->get_name( ) ).

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
* lcl_parser_xml - Deserialisierung
*
* Rekursiver Abstieg ueber den sXML-Reader. Der Kapitelstapel bildet die
* Verschachtelung ab; Textknoten werden nur uebernommen, wenn ein Ziel
* gesetzt ist. Dadurch sind eingerueckte und kompakte XML-Dateien
* gleichermassen lesbar.
*----------------------------------------------------------------------*
CLASS lcl_parser_xml DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS parse
      IMPORTING iv_xml            TYPE string
      RETURNING VALUE(ro_document) TYPE REF TO lcl_document.
ENDCLASS.

CLASS lcl_parser_xml IMPLEMENTATION.

  METHOD parse.

    DATA lo_reader   TYPE REF TO if_sxml_reader.
    DATA lt_stack    TYPE ty_chapters.
    DATA lo_current  TYPE REF TO lcl_chapter.
    DATA lo_object   TYPE REF TO lcl_object.
    DATA ls_meta     TYPE ty_meta.
    DATA ls_row      TYPE ty_row.
    DATA ls_cell     TYPE ty_cell.
    DATA lv_target   TYPE string.

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

            WHEN 'system' OR 'client' OR 'created_by' OR 'created_at' OR 'language'.
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
              CLEAR: lv_otype, lv_oname.
              LOOP AT lt_attr INTO lo_attr.
                CASE lo_attr->qname-name.
                  WHEN 'type'. lv_otype = lo_attr->get_value( ).
                  WHEN 'name'. lv_oname = lo_attr->get_value( ).
                ENDCASE.
              ENDLOOP.
              lo_object = NEW lcl_object( iv_type = lv_otype iv_name = lv_oname ).
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
              WHEN 'system'.        ls_meta-system     = lv_value.
              WHEN 'client'.        ls_meta-client     = lv_value.
              WHEN 'created_by'.    ls_meta-created_by = lv_value.
              WHEN 'created_at'.    ls_meta-created_at = lv_value.
              WHEN 'language'.      ls_meta-language   = lv_value.
              WHEN 'cell'.          ls_cell-value      = lv_value.
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
* lcl_collector_demo - kleines Beispiel anstelle eines echten Collectors
*
* Bildet den in der Spezifikation durchgemessenen IMG-Ausschnitt nach:
* Gliederungskapitel Finanzwesen, darunter die Aktivitaet
* SIMG_CFMENUORFBOBDI mit View V_T007Z.
*----------------------------------------------------------------------*
CLASS lcl_collector_demo DEFINITION.
  PUBLIC SECTION.
    INTERFACES lif_docu_collector.
ENDCLASS.

CLASS lcl_collector_demo IMPLEMENTATION.

  METHOD lif_docu_collector~collect.

    ro_document = NEW lcl_document( ).

    ro_document->set_meta( VALUE ty_meta(
      version    = gc_version
      doc_type   = 'IMG'
      system     = sy-sysid
      client     = sy-mandt
      created_by = sy-uname
      created_at = |{ sy-datum DATE = ISO } { sy-uzeit TIME = ISO }|
      language   = sy-langu ) ).

    DATA(lo_root) = NEW lcl_chapter( iv_id    = '1'
                                     iv_level = 1
                                     iv_type  = 'STRUCTURE'
                                     iv_title = 'Finanzwesen' ).
    ro_document->add_chapter( lo_root ).

    DATA(lo_act) = NEW lcl_chapter( iv_id    = '1.1'
                                    iv_level = 2
                                    iv_type  = 'ACTIVITY'
                                    iv_title = 'Steuerkennzeichen definieren' ).
    lo_root->add_child( lo_act ).

    lo_act->set_reference( VALUE ty_reference(
      activity = 'SIMG_CFMENUORFBOBDI'
      docu_id  = 'SIMGSIMG_CFMENUORFBOBDI'
      tcode    = 'OBDI' ) ).

    lo_act->set_documentation(
      |In dieser Aktivitaet legen Sie die Steuerkennzeichen fest. | &&
      |Umlaute und Sonderzeichen gehoeren mit in den Test: | &&
      |Aenderung, Groesse, <tag> & "Anfuehrung".| ).

    DATA(lo_obj) = NEW lcl_object( iv_type = 'V' iv_name = 'V_T007Z' ).
    lo_act->add_object( lo_obj ).

    lo_obj->add_field( VALUE ty_field( name = 'MANDT' rollname = 'MANDT' keyflag = abap_true ) ).
    lo_obj->add_field( VALUE ty_field( name = 'SPRAS' rollname = 'SPRAS' keyflag = abap_true ) ).
    lo_obj->add_field( VALUE ty_field( name = 'KALSM' rollname = 'KALSM_D' ) ).
    lo_obj->add_field( VALUE ty_field( name = 'MWSKZ' rollname = 'MWSKZ' ) ).
    lo_obj->add_field( VALUE ty_field( name = 'TEXT1' rollname = 'TEXT1_007Z' ) ).

    lo_obj->add_row( VALUE ty_row( cells = VALUE ty_cells(
      ( name = 'MANDT' value = '100' )
      ( name = 'SPRAS' value = 'D' )
      ( name = 'KALSM' value = 'TAXD' )
      ( name = 'MWSKZ' value = 'V0' )
      ( name = 'TEXT1' value = 'Vorsteuer 0 %' ) ) ) ).

    lo_obj->add_row( VALUE ty_row( cells = VALUE ty_cells(
      ( name = 'MANDT' value = '100' )
      ( name = 'SPRAS' value = 'D' )
      ( name = 'KALSM' value = 'TAXD' )
      ( name = 'MWSKZ' value = 'V1' )
      ( name = 'TEXT1' value = 'Vorsteuer 19 %' ) ) ) ).

    " Gesamtzahl im System groesser als die exportierten Zeilen:
    " genau der Fall, den das truncated-Kennzeichen sichtbar machen soll.
    lo_obj->set_row_count( 47 ).
    lo_obj->set_truncated( abap_true ).

    DATA(lo_second) = NEW lcl_chapter( iv_id    = '1.2'
                                       iv_level = 2
                                       iv_type  = 'STRUCTURE'
                                       iv_title = 'Leeres Gliederungskapitel' ).
    lo_root->add_child( lo_second ).

  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* Ablauf
*----------------------------------------------------------------------*
START-OF-SELECTION.

  DATA lo_collector TYPE REF TO lif_docu_collector.
  DATA lo_renderer  TYPE REF TO lif_docu_renderer.

  lo_collector = NEW lcl_collector_demo( ).
  lo_renderer  = NEW lcl_renderer_xml( ).

  " 1. Modell aufbauen
  DATA(lo_doc1) = lo_collector->collect( ).

  " 2. Serialisieren
  DATA(lv_xml1) = lo_renderer->render( lo_doc1 ).

  " 3. Aus dem XML ein neues Modell aufbauen
  DATA(lo_doc2) = lcl_parser_xml=>parse( lv_xml1 ).

  " 4. Erneut serialisieren
  DATA(lv_xml2) = lo_renderer->render( lo_doc2 ).

  " 5. Vergleichen - das ist der Nachweis
  WRITE: / 'Documizer - Roundtrip-Nachweis Kapitelmodell / XML'.
  ULINE.
  WRITE: / 'Zeichen 1. Durchlauf             :', strlen( lv_xml1 ).
  WRITE: / 'Zeichen 2. Durchlauf             :', strlen( lv_xml2 ).

  IF lv_xml1 = lv_xml2.
    WRITE: / 'Ergebnis                         : IDENTISCH - Roundtrip bestanden'.
  ELSE.
    WRITE: / 'Ergebnis                         : ABWEICHUNG - Roundtrip fehlgeschlagen'.
  ENDIF.

  SKIP.
  WRITE: / 'Erzeugtes XML'.
  ULINE.

  DATA(lv_pretty) = lo_renderer->render( io_document = lo_doc1 iv_pretty = abap_true ).
  SPLIT lv_pretty AT cl_abap_char_utilities=>newline INTO TABLE DATA(lt_lines).
  LOOP AT lt_lines INTO DATA(lv_line).
    WRITE: / lv_line.
  ENDLOOP.
