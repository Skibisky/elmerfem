!/******************************************************************************
! *
! *       ELMER, A Computational Fluid Dynamics Program.
! *
! *       Copyright 1st April 1995 - , Center for Scientific Computing,
! *                                    Finland.
! *
! *       All rights reserved. No part of this program may be used,
! *       reproduced or transmitted in any form or by any means
! *       without the written permission of CSC.
! *
! *****************************************************************************/
!
!/******************************************************************************
! *
! *     Module containing interpolation and quadrant tree routines
! *
! ******************************************************************************
! *
! *                     Author:       Juha Ruokolainen
! *
! *                    Address: Center for Scientific Computing
! *                                Tietotie 6, P.O. BOX 405
! *                                  02101 Espoo, Finland
! *                                  Tel. +358 0 457 2723
! *                                Telefax: +358 0 457 2302
! *                              EMail: Juha.Ruokolainen@csc.fi
! *
! *                       Date: 01 Oct 1996
! *
! *                Modified by: Ville Savolainen
! *
! *       Date of modification: 24 Nov 1999
! *
! *****************************************************************************/

MODULE Interpolation

   USE Types
   USE Lists

   USE CoordinateSystems
   USE ElementDescription

   IMPLICIT NONE

 CONTAINS

!------------------------------------------------------------------------------
   SUBROUTINE FindLeafElements( Point, dim, RootQuadrant, LeafQuadrant )
!------------------------------------------------------------------------------
 DLLEXPORT FindLeafElements
!------------------------------------------------------------------------------
     REAL(KIND=dp), DIMENSION(3) :: Point
     REAL(KIND=dp), DIMENSION(6) :: GeometryBoundingBox
     INTEGER :: dim
     TYPE(Quadrant_t), POINTER :: RootQuadrant, LeafQuadrant
!------------------------------------------------------------------------------

     LeafQuadrant => RootQuadrant
     GeometryBoundingBox = RootQuadrant % BoundingBox
!
!    Find recursively the last generation
!    quadrant the point belongs to:
!    -------------------------------------
     CALL FindPointsQuadrant(Point, dim, LeafQuadrant)

   CONTAINS

!------------------------------------------------------------------------------
     RECURSIVE SUBROUTINE FindPointsQuadrant(Point, dim, MotherQuadrant)
!------------------------------------------------------------------------------

     REAL(KIND=dp), DIMENSION(3) :: Point
     INTEGER :: dim
     TYPE(Quadrant_t), POINTER :: MotherQuadrant
!------------------------------------------------------------------------------
     TYPE(Quadrant_t), POINTER :: ChildQuadrant
     INTEGER :: i
     REAL(KIND=dp) :: BBox(6), eps3
     REAL(KIND=dp), PARAMETER :: eps2=0.0d-0 !!!!!!! *** !!!!!!
!------------------------------------------------------------------------------

!    Loop over ChildQuadrants:
!    -------------------------
     DO i=1, 2**dim
        ChildQuadrant => MotherQuadrant % ChildQuadrants(i) % Quadrant
        BBox = ChildQuadrant % BoundingBox
!
!       ******** NOTE: eps2 set to zero at the moment **********
!
        eps3 = eps2 * MAXVAL( BBox(4:6) - BBox(1:3) )
        BBox(1:3) = BBox(1:3) - eps3
        BBox(4:6) = BBox(4:6) + eps3
        !
        ! Is the point in ChildQuadrant(i)?
        ! ----------------------------------
        IF ( (Point(1) >= BBox(1)) .AND. (Point(1) <= BBox(4)) .AND. &
             (Point(2) >= BBox(2)) .AND. (Point(2) <= BBox(5)) .AND. &
             (Point(3) >= BBox(3)) .AND. (Point(3) <= BBox(6)) ) EXIT
     END DO

     IF ( i > 2**dim ) THEN
        PRINT*,'Warning: point not found in any of the quadrants ?'
        NULLIFY( MotherQuadrant )
        RETURN
     END IF

     MotherQuadrant => ChildQuadrant
!
!    Are we already in the LeafQuadrant ?
!    If not, search for the next generation
!    ChildQuadrants for the point:
!    ---------------------------------------
     IF ( ASSOCIATED ( MotherQuadrant % ChildQuadrants ) )THEN
        CALL FindPointsQuadrant( Point, dim, MotherQuadrant )
     END IF
!------------------------------------------------------------------------------
   END SUBROUTINE FindPointsQuadrant
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
 END SUBROUTINE FindLeafElements
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
     FUNCTION PointInElement( Element, ElementNodes, Point, &
          LocalCoordinates, EPS ) RESULT(IsInElement)
!------------------------------------------------------------------------------
 DLLEXPORT PointInElement
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Checks whether a given point belongs to a given bulk element
!    If it does, returns the local coordinates in the bulk element
!  ARGUMENTS:
!
!   Type(Element_t) :: Element
!     INPUT: Bulk element we are checking
!
!   Type(Nodes_t) :: ElementNodes
!     INPUT: The nodal points of the bulk element
!
!   REAL(KIND=dp), DIMENSION(:) :: Point
!     INPUT: Global coordinates of the point we want to check
!
!   REAL(KIND=dp), DIMENSION(:) :: LocalCoordinates
!     INPUT: Local coordinates in the bulk element
!
!  FUNCTION RETURN VALUE:
!    LOGICAL :: IsInBulkElement
!      
!******************************************************************************
    Type(Element_t), POINTER :: Element
    Type(Nodes_t) :: ElementNodes
    LOGICAL :: IsInElement
    REAL(KIND=dp), OPTIONAL :: Eps
    REAL(KIND=dp), DIMENSION(:) :: Point
    REAL(KIND=dp), DIMENSION(:) :: LocalCoordinates
!------------------------------------------------------------------------------
    INTEGER :: n
    INTEGER :: i
    REAL(KIND=dp) :: ug,vg,wg,eps2
!------------------------------------------------------------------------------

!   Initialize:
!   -----------
    Eps2 = 1.0d-12
    IF ( PRESENT( Eps ) ) Eps2 = Eps

    IsInElement = .FALSE.
    n = Element % Type % NumberOfNodes

    IF ( (Point(1) < MINVAL( ElementNodes % x(1:n) ) - eps2* &
        (MAXVAL(ElementNodes % x(1:n)) - MINVAL(ElementNodes % x(1:n)))) &
          .OR. (Point(1) > MAXVAL( ElementNodes % x(1:n) ) + eps2* &
        (MAXVAL(ElementNodes % x(1:n)) - MINVAL(ElementNodes % x(1:n)))) &
          .OR. (Point(2) < MINVAL( ElementNodes % y(1:n) ) - eps2* &
        (MAXVAL(ElementNodes % y(1:n)) - MINVAL(ElementNodes % y(1:n)))) &
          .OR. (Point(2) > MAXVAL( ElementNodes % y(1:n) ) + eps2* &
        (MAXVAL(ElementNodes % y(1:n)) - MINVAL(ElementNodes % y(1:n)))) &
          .OR. (Point(3) < MINVAL( ElementNodes % z(1:n) ) - eps2* &
        (MAXVAL(ElementNodes % z(1:n)) - MINVAL(ElementNodes % z(1:n)))) &
          .OR. (Point(3) > MAXVAL( ElementNodes % z(1:n) ) + eps2* &
        (MAXVAL(ElementNodes % z(1:n)) - MINVAL(ElementNodes % z(1:n)))) &
            )  RETURN
!
!   Get element local coordinates from global
!   coordinates of the point:
!   -----------------------------------------
    CALL GlobalToLocal( ug, vg, wg, Point(1), Point(2), Point(3), &
                    Element, ElementNodes )

    LocalCoordinates(1) = ug
    LocalCoordinates(2) = vg
    LocalCoordinates(3) = wg

    SELECT CASE ( Element % Type % ElementCode / 100 )
      CASE(2)
         IsInElement = (ug<=1.d0 + eps2) .AND. (ug>=-1.d0 - eps2) 

      CASE(3)
         IsInElement = (ug+vg <= 1.d0 + eps2) .AND. &
                       (ug<=1.d0 + eps2) .AND. (ug>=0.d0 - eps2) .AND. &
                       (vg<=1.d0 + eps2) .AND. (vg>=0.d0 - eps2)

      CASE(4)
         IsInElement = ug>=-1.d0-eps2 .AND. ug<=1.d0+eps2 .AND. &
                       vg>=-1.d0-eps2 .AND. vg<=1.d0+eps2

      CASE(5)
         IsInElement = (ug+vg+wg <= 1.d0+eps2) .AND. &
                       (ug<=1.d0+eps2) .AND. (ug>=0.d0-eps2) .AND. &
                       (vg<=1.d0+eps2) .AND. (vg>=0.d0-eps2) .AND. &
                       (wg<=1.d0+eps2) .AND. (wg>=0.d0-eps2)

      CASE(8)
         IsInElement = ug>=-1.d0-eps2 .AND. ug<=1.d0+eps2 .AND. &
                       vg>=-1.d0-eps2 .AND. vg<=1.d0+eps2 .AND. &
                       wg>=-1.d0-eps2 .AND. wg<=1.d0+eps2

    END SELECT
!------------------------------------------------------------------------------
    END FUNCTION PointInElement
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    SUBROUTINE BuildQuadrantTree(Mesh, BoundingBox, RootQuadrant)
!------------------------------------------------------------------------------
 DLLEXPORT BuildQuadrantTree
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Builds a tree hierarchy recursively bisectioning the geometry
!    bounding box, and partitioning the bulk elements in the
!    last level of the tree hierarchy
!
!  ARGUMENTS:
!
!  TYPE(Mesh_t), POINTER :: Mesh
!     INPUT: 
!
!  INTEGER, DIMENSION(6) :: BoundingBox
!     INPUT:  XMin, YMin, ZMin, XMax, YMax, ZMax
!
!  TYPE(Quadrant_t), POINTER :: RootQuadrant
!     OUTPUT: Quadrant tree structure root
!      
!******************************************************************************
!------------------------------------------------------------------------------
    TYPE(Mesh_t) :: Mesh
    REAL(KIND=dp), DIMENSION(6) :: BoundingBox
    TYPE(Quadrant_t), POINTER :: RootQuadrant
!------------------------------------------------------------------------------
    INTEGER :: dim, Generation, i
    REAL(KIND=dp) :: XMin, XMax, YMin, YMax, ZMin, ZMax
    TYPE(Quadrant_t), POINTER :: MotherQuadrant
    INTEGER :: MaxLeafElems

    dim = CoordinateSystemDimension()

    IF ( dim == 3 ) THEN
      MaxLeafElems = 16
    ELSE
      MaxLeafElems = 8
    END IF

    Generation = 0

    XMin = BoundingBox(1)
    XMax = BoundingBox(4)
    IF ( dim >= 2 ) THEN
      YMin = BoundingBox(2)
      YMax = BoundingBox(5)
    ELSE
      YMin = 0.d0
      YMax = 0.d0
    END IF
    IF ( dim == 3) THEN
      ZMin = BoundingBox(3)
      ZMax = BoundingBox(6)
    ELSE
      ZMin = 0.d0
      ZMax = 0.d0
    END IF

! Create Mother of All Quadrants
    ALLOCATE ( RootQuadrant )

    RootQuadrant % BoundingBox = (/ XMin, YMin, ZMin, XMax, YMax, ZMax /)
    RootQuadrant % NElemsInQuadrant = Mesh % NumberOfBulkElements

    ALLOCATE ( RootQuadrant % Elements( Mesh % NumberOfBulkElements ) )
    RootQuadrant % Elements = (/ (i, i=1,Mesh % NumberOfBulkElements) /)

! Start building the quadrant tree
    CALL Info( 'BuildQuandrantTree', 'Start', Level=4 )
    MotherQuadrant => RootQuadrant
    CALL CreateChildQuadrants( MotherQuadrant, dim )
    CALL Info( 'BuildQuandrantTree', 'Ready', Level=4 )

  CONTAINS

!-------------------------------------------------------------------------------
    RECURSIVE SUBROUTINE CreateChildQuadrants( MotherQuadrant, dim )
!-------------------------------------------------------------------------------

!-------------------------------------------------------------------------------
! Model is automatically available (internal subroutine)
!-------------------------------------------------------------------------------
    TYPE(Quadrant_t), POINTER :: MotherQuadrant
    INTEGER :: i, dim, n
    TYPE(QuadrantPointer_t) :: ChildQuadrant(8)
    REAL(KIND=dp) :: XMin, XMax, YMin, YMax, ZMin, ZMax

!-------------------------------------------------------------------------------
! Create 2**dim child quadrants
!-------------------------------------------------------------------------------
    n = 2**dim
    ALLOCATE ( MotherQuadrant % ChildQuadrants(n) )
    DO i=1, n
       ALLOCATE( MotherQuadrant % ChildQuadrants(i) % Quadrant )
       ChildQuadrant(i) % Quadrant => &
            MotherQuadrant % ChildQuadrants(i) % Quadrant
       ChildQuadrant(i) % Quadrant % NElemsInQuadrant = 0
       NULLIFY ( ChildQuadrant(i) % Quadrant % Elements )
       NULLIFY ( ChildQuadrant(i) % Quadrant % ChildQuadrants )
    END DO
!-------------------------------------------------------------------------------
    XMin = MotherQuadrant % BoundingBox(1)
    YMin = MotherQuadrant % BoundingBox(2)
    ZMin = MotherQuadrant % BoundingBox(3)

    XMax = MotherQuadrant % BoundingBox(4)
    YMax = MotherQuadrant % BoundingBox(5)
    ZMax = MotherQuadrant % BoundingBox(6)
    MotherQuadrant % Size = MAX ( MAX( XMax-XMin, YMax-YMin), ZMax-ZMin )

    ChildQuadrant(1) % Quadrant % BoundingBox = (/ XMin, YMin, ZMin, &
      (XMin + XMax)/2.d0, (YMin + YMax)/2.d0, (ZMin + ZMax)/2.d0 /)

    ChildQuadrant(2) % Quadrant % BoundingBox = (/ (XMin+XMax)/2.d0, &
        YMin, ZMin, XMax, (YMin+YMax)/2.d0, (ZMin+ZMax)/2.d0 /)

    IF ( dim >= 2 ) THEN
       ChildQuadrant(3) % Quadrant % BoundingBox = (/ XMin, (YMin+YMax)/2.d0, &
               ZMin, (XMin+XMax)/2.d0, YMax, (ZMin+ZMax)/2.d0 /)

       ChildQuadrant(4) % Quadrant % BoundingBox = (/ (XMin+XMax)/2.d0, &
           (YMin+YMax)/2.d0, ZMin, XMax, YMax, (ZMin+ZMax)/2.d0 /)
    END IF

    IF ( dim == 3 ) THEN
       ChildQuadrant(5) % Quadrant % BoundingBox = (/ XMin, YMin, &
          (ZMin+ZMax)/2.d0, (XMin+XMax)/2.d0, (YMin+YMax)/2.d0, ZMax /)

       ChildQuadrant(6) % Quadrant % BoundingBox = (/ (XMin+XMax)/2.d0, YMin, &
               (ZMin+ZMax)/2.d0, XMax, (YMin+YMax)/2.d0, ZMax /)

       ChildQuadrant(7) % Quadrant % BoundingBox = (/ XMin, (YMin+YMax)/2.d0, &
               (ZMin+ZMax)/2.d0, (XMin+XMax)/2.d0, YMax, ZMax /)

       ChildQuadrant(8) % Quadrant % BoundingBox = (/ (XMin+XMax)/2.d0, &
             (YMin+YMax)/2.d0, (ZMin+ZMax)/2.d0, XMax, YMax, ZMax /)
    END IF
!-------------------------------------------------------------------------------


!-------------------------------------------------------------------------------
! Loop over all elements in the mother quadrant,
! placing them in one of the 2^dim child quadrants
!-------------------------------------------------------------------------------
    CALL PutElementsInChildQuadrants( ChildQuadrant, MotherQuadrant, dim )

!-------------------------------------------------------------------------------
! Check whether we need to branch for the next level
!-------------------------------------------------------------------------------
    DO i=1,n
       ChildQuadrant(i) % Quadrant % Size = MotherQuadrant % Size / 2
       IF ( ChildQuadrant(i) % Quadrant % NElemsInQuadrant > MaxLeafElems ) THEN
          IF ( ChildQuadrant(i) % Quadrant % Size > &
                    ChildQuadrant(i) % Quadrant % MinElementSize ) THEN
             IF ( Generation <= 8 ) THEN
                Generation = Generation + 1
                CALL CreateChildQuadrants( ChildQuadrant(i) % Quadrant, dim )
                Generation = Generation - 1
             END IF
          END IF
       END IF
    END DO

    DEALLOCATE ( MotherQuadrant % Elements )
    NULLIFY ( MotherQuadrant % Elements )
!-------------------------------------------------------------------------------
    END SUBROUTINE CreateChildQuadrants
!-------------------------------------------------------------------------------


!-------------------------------------------------------------------------------
    RECURSIVE SUBROUTINE PutElementsInChildQuadrants( ChildQuadrant, &
                   MotherQuadrant, dim )
!-------------------------------------------------------------------------------
! Loop over all elements in the MotherQuadrant, placing them
! in one of the 2^dim child quadrants
!-------------------------------------------------------------------------------
      TYPE(QuadrantPointer_t) :: ChildQuadrant(8)
      TYPE(Quadrant_t), POINTER :: MotherQuadrant
      INTEGER :: dim
      REAL(KIND=dp) :: eps3
      REAL(KIND=dp), PARAMETER :: eps2=2.5d-2
!-------------------------------------------------------------------------------

      TYPE(Element_t), POINTER :: CurrentElement
      INTEGER :: i, j, t, n
      INTEGER, POINTER :: NodeIndexes(:)
      INTEGER :: ElementList(2**dim, MotherQuadrant % NElemsInQuadrant)

      LOGICAL :: ElementInQuadrant
      REAL(KIND=dp) :: BBox(6), XMin, XMax, YMin, YMax, ZMin, ZMax, ElementSize

!-------------------------------------------------------------------------------

      DO i=1,2**dim
         ChildQuadrant(i) % Quadrant % NElemsInQuadrant = 0
         ChildQuadrant(i) % Quadrant % MinElementSize   = 1.0d20
      END DO

!-------------------------------------------------------------------------------
      DO t=1, MotherQuadrant % NElemsInQuadrant
!-------------------------------------------------------------------------------
         CurrentElement => Mesh % Elements( MotherQuadrant % Elements(t) )
         n = CurrentElement % Type % NumberOfNodes
         NodeIndexes => CurrentElement % NodeIndexes

! Get element coordinates
         XMin = MINVAL( Mesh % Nodes % x(NodeIndexes) )
         XMax = MAXVAL( Mesh % Nodes % x(NodeIndexes) )
         YMin = MINVAL( Mesh % Nodes % y(NodeIndexes) )
         YMax = MAXVAL( Mesh % Nodes % y(NodeIndexes) )
         ZMin = MINVAL( Mesh % Nodes % z(NodeIndexes) )
         ZMax = MAXVAL( Mesh % Nodes % z(NodeIndexes) )
         ElementSize = MAX( MAX( XMax-XMin, YMax-YMin ), ZMax-ZMin )

!-------------------------------------------------------------------------------
! Is the element in one of the child quadrants?:
! Check whether element bounding box crosses any of the child quadrant
! bounding boxes:
!-------------------------------------------------------------------------------
         DO i=1, 2**dim ! loop over child quadrants

            BBox = ChildQuadrant(i) % Quadrant % BoundingBox

            eps3 = 0.0d0
            eps3 = MAX( eps3, BBox(4) - BBox(1) )
            eps3 = MAX( eps3, BBox(5) - BBox(2) )
            eps3 = MAX( eps3, BBox(6) - BBox(3) )
            eps3 = eps2 * eps3

            BBox(1:3) = BBox(1:3) - eps3
            BBox(4:6) = BBox(4:6) + eps3

            ElementInQuadrant = .TRUE.
            IF ( XMax < BBox(1) .OR. XMin > BBox(4) .OR. &
                 YMax < BBox(2) .OR. YMin > BBox(5) .OR. &
                 ZMax < BBox(3) .OR. ZMin > BBox(6) ) ElementInQuadrant = .FALSE.

!-------------------------------------------------------------------------------

            IF ( ElementInQuadrant ) THEN
               ChildQuadrant(i) % Quadrant % NElemsInQuadrant = &
                   ChildQuadrant(i) % Quadrant % NElemsInQuadrant + 1

               ChildQuadrant(i) % Quadrant % MinElementSize = &
                 MIN(ElementSize, ChildQuadrant(i) % Quadrant % MinElementSize)

               ! We allocate and store also the midlevels temporarily
               ! (for the duration of the construction routine):
               ! ----------------------------------------------------
               ElementList(i,ChildQuadrant(i) % Quadrant % NElemsInQuadrant) = &
                               MotherQuadrant % Elements(t) 
            END IF
!-------------------------------------------------------------------------------
         END DO
!-------------------------------------------------------------------------------
      END DO

!-------------------------------------------------------------------------------

      DO i=1,2**dim
         IF ( ChildQuadrant(i) % Quadrant % NElemsInQuadrant /= 0 ) THEN
            ALLOCATE ( ChildQuadrant(i) % Quadrant % Elements ( &
               ChildQuadrant(i) % Quadrant % NElemsInQuadrant ) )

            ChildQuadrant(i) % Quadrant % Elements (1: &
                ChildQuadrant(i) % Quadrant % NElemsInQuadrant) = &
                ElementList(i,1:ChildQuadrant(i) % Quadrant % NElemsInQuadrant)
         END IF
      END DO

!-------------------------------------------------------------------------------
    END SUBROUTINE PutElementsInChildQuadrants
!-------------------------------------------------------------------------------
  END SUBROUTINE BuildQuadrantTree
!-------------------------------------------------------------------------------

!-------------------------------------------------------------------------------
END MODULE Interpolation
!-------------------------------------------------------------------------------
