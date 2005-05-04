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
! ******************************************************************************/
!
!/*******************************************************************************
! *
! *  Module defining element type and operations. The most basic FEM routines
! *  are here, handling the basis functions, global derivatives, etc...
! *
! *******************************************************************************
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
! *                Modified by: 
! *
! *       Date of modification: 31 Jan 2001
! *
! *
! * $Log: ElementDescription.f90,v $
! * Revision 1.87  2005/04/21 06:44:44  jpr
! * *** empty log message ***
! *
! * Revision 1.86  2005/04/19 08:53:46  jpr
! * Renamed module LUDecomposition as LinearAlgebra.
! *
! * Revision 1.85  2005/04/04 06:23:40  jpr
! * *** empty log message ***
! *
! * Revision 1.84  2005/04/04 06:18:27  jpr
! * *** empty log message ***
! *
! * Revision 1.81  2004/09/03 09:16:47  byckling
! * Added p elements
! *
! * Revision 1.80  2004/06/24 12:10:00  jpr
! * *** empty log message ***
! *
! * Revision 1.79  2004/06/10 05:34:18  jpr
! * *** empty log message ***
! *
! * Revision 1.78  2004/04/08 10:00:41  jpr
! * Added point element (code 101) treatment to ElementInfo.
! *
! * Revision 1.77  2004/03/26 12:35:34  jpr
! * *** empty log message ***
! *
! * Revision 1.76  2004/03/04 06:56:09  jpr
! * *** empty log message ***
! *
! * Revision 1.75  2004/03/04 06:34:10  jpr
! * Introduced ELMER_LIB environment variable, which can override
! * ELMER_HOME/lib.
! * Started log.
! *
! *
! * $Id: ElementDescription.f90,v 1.87 2005/04/21 06:44:44 jpr Exp $
! ******************************************************************************/

MODULE ElementDescription

   USE Lists
   USE Integration
   USE GeneralUtils
   USE LinearAlgebra
   USE CoordinateSystems
   ! Use module P element basis functions 
   USE PElementMaps
   USE PElementBase

   IMPLICIT NONE

   INTEGER, PARAMETER,PRIVATE  :: MaxDeg  = 4, MaxDeg3 = MaxDeg**3, &
                           MaxDeg2 = MaxDeg**2

   INTEGER, PARAMETER :: MAX_NODES = 2048

   !
   ! Module global variables
   !
   LOGICAL, PRIVATE :: TypeListInitialized = .FALSE.
   Type(ElementType_t), PRIVATE, POINTER :: ElementTypeList

CONTAINS

!------------------------------------------------------------------------------
   SUBROUTINE AddElementDescription( element,BasisTerms )
DLLEXPORT AddElementDescription
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Add an element description to global list of element types
!
!  ARGUMENTS:
!
!  Type(ElementType_t) :: element
!     INPUT: Structure holding element type description
!
!  INTEGER :: BasisTerms
!     INPUT: List of terms in the basis function that should be included
!            for this element type. BasisTerms(i) is an integer from 1-27
!            according to the list below.
!
!******************************************************************************

      INTEGER, DIMENSION(:) :: BasisTerms
      Type(ElementType_t), TARGET :: element
!------------------------------------------------------------------------------
!     Local variables
!------------------------------------------------------------------------------
      Type(ElementType_t), POINTER :: temp

      INTEGER, DIMENSION(MaxDeg3) :: s
      INTEGER :: i,j,k,l,m,n,upow,vpow,wpow,i1,i2,ii(9),jj

      REAL(KIND=dp) :: u,v,w,r
      REAL(KIND=dp), DIMENSION(:,:), ALLOCATABLE :: A, B
!------------------------------------------------------------------------------

!     PRINT*,'Adding element type: ', element % ElementCode

      n = element % NumberOfNodes
      element % NumberOfEdges = 0
      element % NumberOfFaces = 0
      element % BasisFunctionDegree = 0
      NULLIFY( element % BasisFunctions )

      IF ( element % ElementCode >= 200 ) THEN

      ALLOCATE( A(n,n) )

!------------------------------------------------------------------------------
!     1D bar elements
!------------------------------------------------------------------------------
      IF ( element % DIMENSION == 1 ) THEN

         DO i = 1,n
           u = element % NodeU(i)
           DO j = 1,n
             k = BasisTerms(j) - 1
             upow = k
             IF ( u==0 .AND. upow == 0 ) THEN
                A(i,j) = 1
             ELSE
                A(i,j) = u**upow
             END IF
             element % BasisFunctionDegree = MAX(element % BasisFunctionDegree,upow) 
           END DO
         END DO

!        ALLOCATE( element % BasisFunctions(MaxDeg,MaxDeg) )

!------------------------------------------------------------------------------
!     2D surface elements
!------------------------------------------------------------------------------
      ELSE IF ( element % DIMENSION == 2 ) THEN

         DO i = 1,n
            u = element % NodeU(i)
            v = element % NodeV(i)
            DO j = 1,n
              k = BasisTerms(j) - 1
              vpow = k / MaxDeg 
              upow = MOD(k,MaxDeg)

              IF ( upow == 0 ) THEN
                 A(i,j) = 1
              ELSE
                 A(i,j) = u**upow
              END IF

              IF ( vpow /= 0 ) THEN
                 A(i,j) = A(i,j) * v**vpow
              END IF

              element % BasisFunctionDegree = MAX(element % BasisFunctionDegree,upow) 
              element % BasisFunctionDegree = MAX(element % BasisFunctionDegree,vpow) 
            END DO
         END DO

!        ALLOCATE( element % BasisFunctions(MaxDeg2,MaxDeg2) )

!------------------------------------------------------------------------------
!     3D volume elements
!------------------------------------------------------------------------------
      ELSE

         DO i = 1,n
            u = element % NodeU(i)
            v = element % NodeV(i)
            w = element % NodeW(i)
            DO j = 1,n
              k = BasisTerms(j) - 1
              upow = MOD( k,MaxDeg )
              wpow = k / MaxDeg2
              vpow = MOD( k / MaxDeg, MaxDeg )

              IF ( upow == 0 ) THEN
                 A(i,j) = 1
              ELSE
                 A(i,j) = u**upow
              END IF

              IF ( vpow /= 0 ) THEN
                 A(i,j) = A(i,j) * v**vpow
              END IF

              IF ( wpow /= 0 ) THEN
                 A(i,j) = A(i,j) * w**wpow
              END IF

              element % BasisFunctionDegree = MAX(element % BasisFunctionDegree,upow) 
              element % BasisFunctionDegree = MAX(element % BasisFunctionDegree,vpow) 
              element % BasisFunctionDegree = MAX(element % BasisFunctionDegree,wpow) 
            END DO
         END DO

!        ALLOCATE( element % BasisFunctions(MaxDeg3,MaxDeg3) )
      END IF

!------------------------------------------------------------------------------
!     Compute the coefficients of the basis function terms
!------------------------------------------------------------------------------
      CALL InvertMatrix( A,n )

      IF ( Element % ElementCode == 202 ) THEN
         ALLOCATE( Element % BasisFunctions(14) )
      ELSE
         ALLOCATE( Element % BasisFunctions(n) )
      END IF

      upow = 0
      vpow = 0
      wpow = 0

      DO i = 1,n
        Element % BasisFunctions(i) % n = n
        ALLOCATE( Element % BasisFunctions(i) % p(n) )
        ALLOCATE( Element % BasisFunctions(i) % q(n) )
        ALLOCATE( Element % BasisFunctions(i) % r(n) )
        ALLOCATE( Element % BasisFunctions(i) % Coeff(n) )

        DO j = 1,n
          k = BasisTerms(j) - 1

          SELECT CASE( Element % Dimension ) 
          CASE(1)
             upow = k
          CASE(2)
             vpow = k / MaxDeg 
             upow = MOD(k,MaxDeg)
          CASE(3)
             upow = MOD( k,MaxDeg )
             wpow = k / MaxDeg2
             vpow = MOD( k / MaxDeg, MaxDeg )
           END SELECT

           Element % BasisFunctions(i) % p(j) = upow
           Element % BasisFunctions(i) % q(j) = vpow
           Element % BasisFunctions(i) % r(j) = wpow
           Element % BasisFunctions(i) % Coeff(j) = A(j,i)
        END DO
      END DO

      DEALLOCATE( A )

      IF ( Element % ElementCode == 202 ) THEN
         ALLOCATE( A(14,14) )
         A = 0
         CALL Compute1DPBasis( A,14 )

         DO i=3,14
            ALLOCATE( Element % BasisFunctions(i) % p(i) )
            ALLOCATE( Element % BasisFunctions(i) % q(i) )
            ALLOCATE( Element % BasisFunctions(i) % r(i) )
            ALLOCATE( Element % BasisFunctions(i) % Coeff(i) )

            k = 0
            DO j=1,i
               IF ( A(i,j) /= 0.0d0 ) THEN
                  k = k + 1
                  Element % BasisFunctions(i) % p(k) = j-1
                  Element % BasisFunctions(i) % q(k) = 0
                  Element % BasisFunctions(i) % r(k) = 0
                  Element % BasisFunctions(i) % Coeff(k) = A(i,j)
               END IF
            END DO
            Element % BasisFunctions(i) % n = k
         END DO
         DEALLOCATE( A )
      END IF

!------------------------------------------------------------------------------

      SELECT CASE( Element % ElementCode / 100 )
        CASE(3) 
           Element % NumberOfEdges = 3
        CASE(4) 
           Element % NumberOfEdges = 4
        CASE(5) 
           Element % NumberOfFaces = 4
           Element % NumberOfEdges = 6
        CASE(6) 
           Element % NumberOfFaces = 5
           Element % NumberOfEdges = 8
        CASE(7) 
           Element % NumberOfFaces = 5
           Element % NumberOfEdges = 9
        CASE(8) 
           Element % NumberOfFaces = 6
           Element % NumberOfEdges = 12
      END SELECT

      END IF ! type >= 200

!------------------------------------------------------------------------------
!     And finally add the element description to the global list of types
!------------------------------------------------------------------------------
      IF ( .NOT.TypeListInitialized ) THEN
        ALLOCATE( ElementTypeList )
        ElementTypeList = element
        TypeListInitialized = .TRUE.
        NULLIFY( ElementTypeList % NextElementType )
      ELSE
        ALLOCATE( temp )
        temp = element
        temp % NextElementType => ElementTypeList
        ElementTypeList => temp
      END IF

!------------------------------------------------------------------------------

CONTAINS


!------------------------------------------------------------------------------
   SUBROUTINE Compute1DPBasis( Basis,n )
!------------------------------------------------------------------------------
! Subroutine to compute 1D P-basis from Legendre polynomials.
!------------------------------------------------------------------------------
     INTEGER :: n
     REAL(KIND=dp) :: Basis(:,:)
!------------------------------------------------------------------------------
     REAL(KIND=dp)   :: s,P(n+1),Q(n),P0(n),P1(n+1)
     INTEGER :: i,j,k,np,info

!------------------------------------------------------------------------------

     IF ( n <= 1 ) THEN
        Basis(1,1)     = 1.0d0
        RETURN
     END IF
!------------------------------------------------------------------------------
! Compute coefficients of n:th Legendre polynomial from the recurrence:
!
! (i+1)P_{i+1}(x) = (2i+1)*x*P_i(x) - i*P_{i-1}(x), P_{0} = 1; P_{1} = x;
!
! CAVEAT: Computed coefficients inaccurate for n > ~15
!------------------------------------------------------------------------------
     P = 0
     P0 = 0
     P1 = 0
     P0(1) = 1
     P1(1) = 1
     P1(2) = 0

     Basis(1,1) =  0.5d0
     Basis(1,2) = -0.5d0

     Basis(2,1) =  0.5d0
     Basis(2,2) =  0.5d0

     DO k=2,n
       IF ( k > 2 ) THEN
          s = SQRT( (2.0d0*(k-1)-1) / 2.0d0 )
          DO j=1,k-1
             Basis(k,k-j+1) = s * P0(j) / (k-j)
             Basis(k,1) = Basis(k,1) - s * P0(j)*(-1)**(j+1) / (k-j)
          END DO
       END IF

       i = k - 1
       P(1:i+1) = (2*i+1) * P1(1:i+1)  / (i+1)
       P(3:i+2) = P(3:i+2) - i*P0(1:i) / (i+1)
       P0(1:i+1) = P1(1:i+1)
       P1(1:i+2) = P(1:i+2)
     END DO
!--------------------------------------------------------------------------
 END SUBROUTINE Compute1DPBasis
!--------------------------------------------------------------------------

   END SUBROUTINE AddElementDescription 
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   SUBROUTINE InitializeElementDescriptions
DLLEXPORT InitializeElementDescriptions
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Read the element description input file and add the element types to a
!    global list. The file is assumed to be found under the name
!
!        $ELMER_HOME/lib/elements.def
!
!   This is the first routine the user of the element utilities should call
!   in his/her code.
!******************************************************************************
!
!------------------------------------------------------------------------------
!     Local variables
!------------------------------------------------------------------------------
      INTEGER, PARAMETER :: MAXLEN = 512
      CHARACTER(LEN=MAXLEN) :: str,elmer_home

      INTEGER :: k
      INTEGER, DIMENSION(MaxDeg3) :: BasisTerms

      Type(ElementType_t) :: element

      LOGICAL :: gotit
!------------------------------------------------------------------------------
!     PRINT*,' '
!     PRINT*,'----------------------------------------------'
!     PRINT*,'Reading element definition file: elements.def'
!     PRINT*,'----------------------------------------------'


      !
      ! Add connectivity element types:
      ! -------------------------------
      BasisTerms = 0
      element % GaussPoints  = 0
      element % GaussPoints2 = 0
      NULLIFY( element % NodeU )
      NULLIFY( element % NodeV )
      NULLIFY( element % NodeW )
      DO k=3,64
        element % NumberOfNodes = k
        element % ElementCode = 100 + k
        CALL AddElementDescription( element,BasisTerms )
      END DO

      ! then the rest of them....
      !--------------------------
      str = 'ELMER_LIB'; str(10:10) = CHAR(0)
      CALL envir( str,elmer_home,k ) 

      IF (  k > 0 ) THEN
         WRITE( str, '(a,a)' ) elmer_home(1:k),'/elements.def'
      ELSE
        str = 'ELMER_HOME'; str(11:11) = CHAR(0)
        CALL envir( str,elmer_home,k ) 

        IF ( k > 0 ) THEN
          WRITE( str, '(a,a)' ) elmer_home(1:k),'/lib/elements.def'
        ELSE
          WRITE( str, '(a)' )   'lib/elements.def'
        END IF
      END IF

      OPEN( 1,FILE=TRIM(str), STATUS='OLD' )

      DO WHILE( ReadAndTrim(1,str) )

        IF ( str(1:7) == 'element' ) THEN

          BasisTerms = 0

          NULLIFY( element % NodeU )
          NULLIFY( element % NodeV )
          NULLIFY( element % NodeW )

          gotit = .FALSE.
          DO WHILE( ReadAndTrim(1,str) )

            IF ( str(1:9) == 'dimension' ) THEN
              READ( str(10:MAXLEN), * ) element % Dimension

            ELSE IF ( str(1:4) == 'code' ) THEN
              READ( str(5:MAXLEN), * ) element % ElementCode

            ELSE IF ( str(1:5) == 'nodes' ) THEN
              READ( str(6:MAXLEN), * ) element % NumberOfNodes

            ELSE IF ( str(1:6) == 'node u' ) THEN
              ALLOCATE( element % NodeU(element % NumberOfNodes) )
              READ( str(7:MAXLEN), * ) (element % NodeU(k),k=1,element % NumberOfNodes)

            ELSE IF ( str(1:6) == 'node v' ) THEN
              ALLOCATE( element % NodeV(element % NumberOfNodes) )
              READ( str(7:MAXLEN), * ) (element % NodeV(k),k=1,element % NumberOfNodes)

            ELSE IF ( str(1:6) == 'node w' ) THEN
              ALLOCATE( element % NodeW(element % NumberOfNodes ) )
              READ( str(7:MAXLEN), * ) (element % NodeW(k),k=1,element % NumberOfNodes)

            ELSE IF ( str(1:5) == 'basis' ) THEN
              READ( str(6:MAXLEN), * ) (BasisTerms(k),k=1,element % NumberOfNodes)

            ELSE IF ( str(1:13) == 'stabilization' ) THEN
              READ( str(14:MAXLEN), * ) element % StabilizationMK

            ELSE IF ( str(1:12) == 'gauss points' ) THEN

              Element % GaussPoints2 = 0
              READ( str(13:MAXLEN), *,END=10 ) element % GaussPoints,element % GaussPoints2

10            CONTINUE

              IF ( Element % GaussPoints2 <= 0 ) &
                   Element % GaussPoints2 = Element % GaussPoints
            ELSE IF ( str(1:3) == 'end' ) THEN
              gotit = .TRUE.
              EXIT
            END IF
          END DO

          IF ( gotit ) THEN
            Element % StabilizationMK = 0.0d0
            IF ( .NOT.ASSOCIATED( element % NodeV ) ) THEN
              ALLOCATE( element % NodeV(element % NumberOfNodes) )
              element % NodeV = 0.0d0
            END IF

            IF ( .NOT.ASSOCIATED( element % NodeW ) ) THEN
              ALLOCATE( element % NodeW(element % NumberOfNodes) )
              element % NodeW = 0.0d0
            END IF

            CALL AddElementDescription( element,BasisTerms )
          ELSE
            IF ( ASSOCIATED( element % NodeU ) ) DEALLOCATE( element % NodeU )
            IF ( ASSOCIATED( element % NodeV ) ) DEALLOCATE( element % NodeV )
            IF ( ASSOCIATED( element % NodeW ) ) DEALLOCATE( element % NodeW )
          END IF
        END IF
      END DO

      CLOSE(1)
!------------------------------------------------------------------------------
   END SUBROUTINE InitializeElementDescriptions
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   FUNCTION GetElementType( code,CompStabFlag ) RESULT(element)
DLLEXPORT GetElementType
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Given element type code return pointer to the corresponding element type
!    structure.
!    
!******************************************************************************
!
      INTEGER :: code
      LOGICAL, OPTIONAL :: CompStabFlag
      Type(ElementType_t), POINTER :: element
!------------------------------------------------------------------------------
!     Local variables
!------------------------------------------------------------------------------
      Type(Nodes_t) :: Nodes
      Type(Element_t), POINTER :: Elm
!------------------------------------------------------------------------------
      element => ElementTypeList

      DO WHILE( ASSOCIATED(element) )
        IF ( code == element % ElementCode ) EXIT
        element => element % NextElementType
      END DO

      IF ( .NOT. ASSOCIATED( element ) ) THEN
        WRITE( message, * ) &
             'Element type code ',code,' not found. Ignoring element.'
        CALL Warn( 'GetElementType', message )
        RETURN
      END IF

      IF ( PRESENT( CompStabFlag ) ) THEN
        IF ( .NOT. CompStabFlag ) RETURN
      END IF

      IF ( Element % StabilizationMK == 0.0d0 ) THEN
        ALLOCATE( Elm )
        Elm % Type => element
        Elm % BDOFs  = 0
        Elm % DGDOFs = 0
        NULLIFY( Elm % PDefs )
        NULLIFY( Elm % DGIndexes )
        NULLIFY( Elm % EdgeIndexes )
        NULLIFY( Elm % FaceIndexes )
        NULLIFY( Elm % BubbleIndexes )
        Nodes % x => Element % NodeU
        Nodes % y => Element % NodeV
        Nodes % z => Element % NodeW
        CALL StabParam( Elm, Nodes, Element % NumberOfNodes, &
                 Element % StabilizationMK )

        DEALLOCATE(Elm)
      END IF

   END FUNCTION GetElementType
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE StabParam(Element,Nodes,n,mK,hK)
!------------------------------------------------------------------------------
!
! Compute convection diffusion equation stab. parameter  for each and every
! element of the model by solving the largest eigenvalue of
!
! Lu = \lambda Gu,
!
! L = (\nablda^2 u,\nabla^ w), G = (\nabla u,\nabla w)
!
!
!------------------------------------------------------------------------------
DLLEXPORT StabParam
!------------------------------------------------------------------------------
      IMPLICIT NONE

      Type(Element_t), POINTER :: Element
      INTEGER :: n
      Type(Nodes_t) :: Nodes
      REAL(KIND=dp) :: mK
      REAL(KIND=dp), OPTIONAL :: hK
!------------------------------------------------------------------------------
      INTEGER :: info,p,q,i,j,t,dim
      REAL(KIND=dp) :: EIGR(n),EIGI(n),Beta(n),s,ddp(3),ddq(3)
      REAL(KIND=dp) :: u,v,w,L(n-1,n-1),G(n-1,n-1),Work(16*n)
      REAL(KIND=dp) :: Basis(n),dBasisdx(n,3),ddBasisddx(n,3,3),detJ

      LOGICAL :: stat
      Type(GaussIntegrationPoints_t) :: IntegStuff

      IF ( Element % Type % ElementCode == 613 ) RETURN

      IF ( Element % Type % BasisFunctionDegree <= 1 ) THEN
         SELECT CASE( Element % Type % ElementCode ) 
           CASE( 202, 303, 404, 504, 605, 706  )
              mK = 1.0d0 / 3.0d0
           CASE( 808 )
              mK = 1.0d0 / 6.0d0
         END SELECT
         IF ( PRESENT( hK ) ) hK = ElementDiameter( Element, Nodes )
         RETURN
      END IF

      dim = CoordinateSystemDimension()

      IntegStuff = GaussPoints( Element )
      L = 0.0d0
      G = 0.0d0
      DO t=1,IntegStuff % n
        u = IntegStuff % u(t)
        v = IntegStuff % v(t)
        w = IntegStuff % w(t)

        stat = ElementInfo( Element,Nodes,u,v,w,detJ,Basis, &
                dBasisdx, ddBasisddx, .TRUE. )

        s = detJ * IntegStuff % s(t)

        DO p=2,n
          DO q=2,n
            ddp = 0.0d0
            ddq = 0.0d0
            DO i=1,dim
              ddp(i) = ddp(i) + ddBasisddx(p,i,i)
              ddq(i) = ddq(i) + ddBasisddx(q,i,i)
              G(p-1,q-1) = G(p-1,q-1) + s * dBasisdx(p,i) * dBasisdx(q,i)
            END DO
            L(p-1,q-1) = L(p-1,q-1) + s * SUM(ddp) * SUM(ddq)
          END DO
        END DO
      END DO

      IF ( ALL(ABS(L) < AEPS) ) THEN
        mK = 1.0d0 / 3.0d0
        IF ( PRESENT(hK) ) THEN
          hK = ElementDiameter( Element,Nodes )
        END IF
        RETURN
      END IF

      CALL DSYGV( 1,'N','U',n-1,L,n-1,G,n-1,EIGR,Work,12*n,info )
      mK = EIGR(n-1)

      IF ( mK < 10*AEPS ) THEN
        mK = 1.0d0 / 3.0d0
        IF ( PRESENT(hK) ) THEN
          hK = ElementDiameter( Element,Nodes )
        END IF
        RETURN
      END IF

      IF ( PRESENT( hK ) ) THEN
        hK = SQRT( 2.0d0 / (mK * Element % Type % StabilizationMK) )
        mK = MIN( 1.0d0 / 3.0d0, Element % Type % StabilizationMK )
      ELSE
        SELECT CASE(Element % Type % ElementCode / 100)
        CASE(2,4,8) 
          mK = 4 * mK
        END SELECT
        mK = MIN( 1.0d0/3.0d0, 2/mK )
      END IF

!------------------------------------------------------------------------------
   END SUBROUTINE StabParam
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
   FUNCTION InterpolateInElement1D( element,x,u ) RESULT(y)
DLLEXPORT InterpolateInElement1D
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!   Given element structure return value of a quantity x given at element nodes
!   at local coordinate point u inside the element. Element basis functions are
!   used to compute the value. This is for 1D elements, and shouldnt propably
!   be called directly by the user but trough the wrapper routine
!   InterpolateInElement.
!
!  ARGUMENTS:
!   Type(Element_t) :: element
!     INPUT: element structure
!     
!    REAL(KIND=dp) :: x(:)
!     INPUT: Nodal values of the quantity whose value we want to know
!
!    REAL(KIND=dp) :: u
!     INPUT: Point at which to evaluate the value
!
!  FUNCTION VALUE:
!     REAL(KIND=dp) :: y
!      value of the quantity y = x(u)
!    
!******************************************************************************

     Type(Element_t) :: element
     REAL(KIND=dp) :: u
     REAL(KIND=dp), DIMENSION(:) :: x

!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
     REAL(KIND=dp) :: y,s

     INTEGER :: i,j,k,n

     Type(ElementType_t), POINTER :: elt

     REAL(KIND=dp), POINTER :: Coeff(:)
     INTEGER, POINTER :: p(:)
     TYPE(BasisFunctions_t), POINTER :: BasisFunctions(:)
!------------------------------------------------------------------------------

     elt => element % Type
     BasisFunctions => elt % BasisFunctions
     k = Elt % NumberOfNodes + Element % BDOFs

     y = 0.0d0
     DO n=1,k
       IF ( x(n) /= 0.0d0 ) THEN
          p => BasisFunctions(n) % p
          Coeff => BasisFunctions(n) % Coeff

          s = 0.0d0
          DO i=1,BasisFunctions(n) % n
             s = s + Coeff(i) * u**p(i)
          END DO
          y = y + s * x(n)
       END IF
     END DO
   END FUNCTION InterpolateInElement1D
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   FUNCTION FirstDerivative1D( element,x,u ) RESULT(y)
DLLEXPORT FirstDerivative1D
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!   Given element structure return value of the first partial derivative with
!   respect to local coordinate of a quantity x given at element nodes at local
!   coordinate point u inside the element. Element basis functions are used to
!   compute the value. 
!
!  ARGUMENTS:
!   Type(Element_t) :: element
!     INPUT: element structure
!     
!    REAL(KIND=dp) :: x(:)
!     INPUT: Nodal values of the quantity whose partial derivative we want to know
!
!    REAL(KIND=dp) :: u
!     INPUT: Point at which to evaluate the partial derivative
!
!  FUNCTION VALUE:
!     REAL(KIND=dp) :: y
!      value of the quantity y = @x/@u
!    
!******************************************************************************

     Type(Element_t) :: element
     REAL(KIND=dp) :: u
     REAL(KIND=dp), DIMENSION(:) :: x
!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
     REAL(KIND=dp) :: y

     INTEGER :: i,j,k,n,l

     Type(ElementType_t), POINTER :: elt

     REAL(KIND=dp) :: s

     REAL(KIND=dp), POINTER :: Coeff(:)
     INTEGER, POINTER :: p(:)
     TYPE(BasisFunctions_t), POINTER :: BasisFunctions(:)

     elt => element % Type
     BasisFunctions => elt % BasisFunctions
     k = Elt % NumberOfNodes + Element % BDOFs

     y = 0.0d0
     DO n=1,k
       IF ( x(n) /= 0.0d0 ) THEN
          p => BasisFunctions(n) % p
          Coeff => BasisFunctions(n) % Coeff

          s = 0.0d0
          DO i=1,BasisFunctions(n) % n
             IF ( p(i) >= 1 ) THEN 
                s = s + p(i) * Coeff(i) * u**(p(i)-1)
             END IF
          END DO
          y = y + s * x(n)
       END IF
     END DO
   END FUNCTION FirstDerivative1D
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   FUNCTION SecondDerivatives1D( element,x,u ) RESULT(y)
DLLEXPORT SecondDerivatives1D
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!   Given element structure return value of the second partial derivative with
!   respect to local coordinate of a quantity x given at element nodes at local
!   coordinate point u inside the element. Element basis functions are used to
!   compute the value. 
!
!  ARGUMENTS:
!   Type(Element_t) :: element
!     INPUT: element structure
!     
!    REAL(KIND=dp) :: x(:)
!     INPUT: Nodal values of the quantity whose partial derivative we want to know
!
!    REAL(KIND=dp) :: u
!     INPUT: Point at which to evaluate the partial derivative
!
!  FUNCTION VALUE:
!     REAL(KIND=dp) :: y
!      value of the quantity y = @x/@u
!    
!******************************************************************************

     Type(Element_t) :: element
     REAL(KIND=dp) :: u
     REAL(KIND=dp), DIMENSION(:) :: x
!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
     REAL(KIND=dp) :: usum,y

     INTEGER :: i,j,k,n

     Type(ElementType_t), POINTER :: elt

     INTEGER, POINTER :: p(:),q(:)
     REAL(KIND=dp), POINTER :: Coeff(:)

     REAL(KIND=dp) :: s
     TYPE(BasisFunctions_t), POINTER :: BasisFunctions(:)

     elt => element % Type
     BasisFunctions => elt % BasisFunctions
     k = Elt % NumberOfNodes + Element % BDOFs

     y = 0.0d0
     DO n=1,k
       IF ( x(n) /= 0.0d0 ) THEN
          p => BasisFunctions(n) % p
          Coeff => BasisFunctions(n) % Coeff

          s = 0.0d0
          DO i=1,BasisFunctions(n) % n
             IF ( p(i) >= 2 ) THEN
                s = s + p(i) * (p(i)-1) * Coeff(i) * u**(p(i)-2)
             END IF
          END DO
          y = y + s * x(n)
       END IF
     END DO
   END FUNCTION SecondDerivatives1D
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   FUNCTION InterpolateInElement2D( element,x,u,v ) RESULT(y)
DLLEXPORT InterpolateInElement2D
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!   Given element structure return value of a quantity x given at element nodes
!   at local coordinate point (u,vb) inside the element. Element basis functions
!   are used to compute the value.This is for 2D elements, and shouldnt propably
!   be called directly by the user but trough the wrapper routine
!   InterpolateInElement.
!
!  ARGUMENTS:
!   Type(Element_t) :: element
!     INPUT: element structure
!     
!    REAL(KIND=dp) :: x(:)
!     INPUT: Nodal values of the quantity whose value we want to know
!
!    REAL(KIND=dp) :: u
!     INPUT: Point at which to evaluate the value
!
!  FUNCTION VALUE:
!     REAL(KIND=dp) :: y
!      value of the quantity y = x(u,v)
!    
!******************************************************************************
   !
   ! Return value of a quantity x at point u,v
   !
   !
   !
      Type(Element_t) :: element

      REAL(KIND=dp) :: u,v
      REAL(KIND=dp), DIMENSION(:) :: x
!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
      REAL(KIND=dp) :: y,s,t

      INTEGER :: i,j,k,m,n

      Type(ElementType_t),POINTER :: elt
      REAL(KIND=dp), POINTER :: Coeff(:)
      INTEGER, POINTER :: p(:),q(:)
      TYPE(BasisFunctions_t), POINTER :: BasisFunctions(:)
!------------------------------------------------------------------------------

      elt => element % Type
      BasisFunctions => elt % BasisFunctions

      y = 0.0d0
      DO n = 1,elt % NumberOfNodes
        IF ( x(n) /= 0.0d0 ) THEN
          p => BasisFunctions(n) % p
          q => BasisFunctions(n) % q
          Coeff => BasisFunctions(n) % Coeff

          s = 0.0d0
          DO i = 1,BasisFunctions(n) % n
             s = s + Coeff(i) * u**p(i) * v**q(i)
          END DO
          y = y + s*x(n)
        END IF
      END DO

   END FUNCTION InterpolateInElement2D
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   FUNCTION FirstDerivativeInU2D( element,x,u,v ) RESULT(y)
DLLEXPORT FirstDerivativeInU2D
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!   Given element structure return value of the first partial derivative with
!   respect to local coordinate u of i quantity x given at element nodes at local
!   coordinate point u,v inside the element. Element basis functions are used to
!   compute the value. 
!
!  ARGUMENTS:
!   Type(Element_t) :: element
!     INPUT: element structure
!     
!    REAL(KIND=dp) :: x(:)
!     INPUT: Nodal values of the quantity whose partial derivative we want to know
!
!    REAL(KIND=dp) :: u,v
!     INPUT: Point at which to evaluate the partial derivative
!
!  FUNCTION VALUE:
!     REAL(KIND=dp) :: y
!      value of the quantity y = @x(u,v)/@u
!    
!******************************************************************************
   !
   ! Return first partial derivative in u of a quantity x at point u,v
   !
   !
   !

      Type(Element_t) :: element

      REAL(KIND=dp) :: u,v
      REAL(KIND=dp), DIMENSION(:) :: x

!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------

      REAL(KIND=dp) :: y,s,t

      Type(ElementType_t),POINTER :: elt
      REAL(KIND=dp), POINTER :: Coeff(:)
      INTEGER, POINTER :: p(:),q(:)
      TYPE(BasisFunctions_t), POINTER :: BasisFunctions(:)

      INTEGER :: i,j,k,m,n

      elt => element % Type
      BasisFunctions => elt % BasisFunctions

      y = 0.0d0
      DO n = 1,elt % NumberOfNodes
        IF ( x(n) /= 0.0d0 ) THEN
          p => BasisFunctions(n) % p
          q => BasisFunctions(n) % q
          Coeff => BasisFunctions(n) % Coeff

          s = 0.0d0
          DO i = 1,BasisFunctions(n) % n
             IF ( p(i) >= 1 ) THEN
               s = s + p(i) * Coeff(i) * u**(p(i)-1) * v**q(i)
            END IF
          END DO
          y = y + s*x(n)
        END IF
      END DO

   END FUNCTION FirstDerivativeInU2D
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   FUNCTION FirstDerivativeInV2D( element,x,u,v ) RESULT(y)
DLLEXPORT FirstDerivativeInV2D
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!   Given element structure return value of the first partial derivative with
!   respect to local coordinate v of i quantity x given at element nodes at local
!   coordinate point u,v inside the element. Element basis functions are used to
!   compute the value. 
!
!  ARGUMENTS:
!   Type(Element_t) :: element
!     INPUT: element structure
!     
!    REAL(KIND=dp) :: x(:)
!     INPUT: Nodal values of the quantity whose partial derivative we want to know
!
!    REAL(KIND=dp) :: u,v
!     INPUT: Point at which to evaluate the partial derivative
!
!  FUNCTION VALUE:
!     REAL(KIND=dp) :: y
!      value of the quantity y = @x(u,v)/@v
!    
!******************************************************************************
    !
    ! Return first partial derivative in v of a quantity x at point u,v
    !
    !
    !
      Type(Element_t) :: element

      REAL(KIND=dp), DIMENSION(:) :: x
      REAL(KIND=dp) :: u,v

!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
      REAL(KIND=dp) :: y,s,t

      Type(ElementType_t),POINTER :: elt
      REAL(KIND=dp), POINTER :: Coeff(:)
      INTEGER, POINTER :: p(:),q(:)
      TYPE(BasisFunctions_t), POINTER :: BasisFunctions(:)

      INTEGER :: i,j,k,m,n

      elt => element % Type
      BasisFunctions => elt % BasisFunctions

      y = 0.0d0
      DO n = 1,elt % NumberOfNodes
        IF ( x(n) /= 0.0d0 ) THEN
          p => BasisFunctions(n) % p
          q => BasisFunctions(n) % q
          Coeff => BasisFunctions(n) % Coeff

          s = 0.0d0
          DO i = 1,BasisFunctions(n) % n
             IF ( q(i) >= 1  ) THEN
                s = s + q(i) * Coeff(i) * u**p(i) * v**(q(i)-1)
             END IF
          END DO
          y = y + s*x(n)
        END IF
      END DO

   END FUNCTION FirstDerivativeInV2D
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   FUNCTION SecondDerivatives2D( element,x,u,v ) RESULT(ddx)
DLLEXPORT SecondDerivatives2D
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!   Given element structure return value of the second partial derivatives with
!   respect to local coordinates of a quantity x given at element nodes at local
!   coordinate point u,v inside the element. Element basis functions are used to
!   compute the value. 
!
!  ARGUMENTS:
!   Type(Element_t) :: element
!     INPUT: element structure
!     
!    REAL(KIND=dp) :: x(:)
!     INPUT: Nodal values of the quantity whose partial derivatives we want to know
!
!    REAL(KIND=dp) :: u,v
!     INPUT: Point at which to evaluate the partial derivative
!
!  FUNCTION VALUE:
!     REAL(KIND=dp) :: s
!      value of the quantity s = @^2x(u,v)/@v^2
!    
!******************************************************************************

      Type(Element_t) :: element

      REAL(KIND=dp), DIMENSION(:) :: x
      REAL(KIND=dp) :: u,v

!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
      Type(ElementType_t),POINTER :: elt
      REAL(KIND=dp), DIMENSION (2,2) :: ddx
      TYPE(BasisFunctions_t), POINTER :: BasisFunctions(:)

      REAL(KIND=dp) :: s,t
      INTEGER, POINTER :: p(:),q(:)
      REAL(KIND=dp), POINTER :: Coeff(:)

      INTEGER :: i,j,k,n,m

!------------------------------------------------------------------------------
      elt => element % Type
      k = elt % NumberOfNodes
      BasisFunctions => elt % BasisFunctions

      ddx = 0.0d0

      DO n = 1,k
        IF ( x(n) /= 0.0d0 ) THEN
          p => BasisFunctions(n) % p
          q => BasisFunctions(n) % q
          Coeff => BasisFunctions(n) % Coeff
!------------------------------------------------------------------------------
!         @^2x/@u^2
!------------------------------------------------------------------------------
          s = 0.0d0
          DO i = 1, BasisFunctions(n) % n
             IF ( p(i) >= 2 ) THEN
                s = s + p(i) * (p(i)-1) * Coeff(i) * u**(p(i)-2) * v**q(i)
             END IF
          END DO
          ddx(1,1) = ddx(1,1) + s*x(n)

!------------------------------------------------------------------------------
!         @^2x/@u@v
!------------------------------------------------------------------------------
          s = 0.0d0
          DO i = 1, BasisFunctions(n) % n
              IF ( p(i) >= 1 .AND. q(i) >= 1 ) THEN
                 s = s + p(i) * q(i) * Coeff(i) * u**(p(i)-1) * v**(q(i)-1)
              END IF
          END DO
          ddx(1,2) = ddx(1,2) + s*x(n)

!------------------------------------------------------------------------------
!         @^2x/@v^2
!------------------------------------------------------------------------------
          s = 0.0d0
          DO i = 1, BasisFunctions(n) % n
             IF ( q(i) >= 2 ) THEN
                s = s + q(i) * (q(i)-1) * Coeff(i) * u**p(i) * v**(q(i)-2)
             END IF
          END DO
          ddx(2,2) = ddx(2,2) + s*x(n)
        END IF
      END DO

      ddx(2,1) = ddx(1,2)

   END FUNCTION SecondDerivatives2D
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   FUNCTION InterpolateInElement3D( element,x,u,v,w ) RESULT(y)
DLLEXPORT InterpolateInElement3D
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!   Given element structure return value of a quantity x given at element nodes
!   at local coordinate point (u,v,w) inside the element. Element basis functions
!   are used to compute the value. This is for 3D elements, and shouldnt propably
!   be called directly by the user but trough the wrapper routine
!   InterpolateInElement.
!
!  ARGUMENTS:
!   Type(Element_t) :: element
!     INPUT: element structure
!     
!    REAL(KIND=dp) :: x(:)
!     INPUT: Nodal values of the quantity whose value we want to know
!
!    REAL(KIND=dp) :: u,v,w
!     INPUT: Point at which to evaluate the value
!
!  FUNCTION VALUE:
!     REAL(KIND=dp) :: y
!      value of the quantity y = x(u,v,w)
!    
!******************************************************************************
   !
   ! Return value of a quantity x at point u,v,w
   !
      Type(Element_t) :: element

      REAL(KIND=dp) :: u,v,w
      REAL(KIND=dp), DIMENSION(:) :: x
!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
      REAL(KIND=dp) :: y

      Type(ElementType_t),POINTER :: elt

      INTEGER :: i,j,k,l,n,m

      REAL(KIND=dp) :: s,t
      INTEGER, POINTER :: p(:),q(:), r(:)
      REAL(KIND=dp), POINTER :: Coeff(:)
      TYPE(BasisFunctions_t), POINTER :: BasisFunctions(:)
!------------------------------------------------------------------------------

      elt => element % Type
      l = elt % BasisFunctionDegree
      BasisFunctions => elt % BasisFunctions

IF ( Elt % ElementCode == 605 ) THEN
  s = 0.0d0
  IF ( w == 1 ) w = 1.0d0-1.0d-12
  s = 1.0d0 / (1-w)

  y = 0.0d0
  y = y + x(1) * ( (1-u) * (1-v) - w + u*v*w * s ) / 4
  y = y + x(2) * ( (1+u) * (1-v) - w - u*v*w * s ) / 4
  y = y + x(3) * ( (1+u) * (1+v) - w + u*v*w * s ) / 4
  y = y + x(4) * ( (1-u) * (1+v) - w - u*v*w * s ) / 4
  y = y + x(5) * w
  RETURN
ELSE IF ( Elt % ElementCode == 613 ) THEN
  IF ( w == 1 ) w = 1.0d0-1.0d-12
  s = 1.0d0 / (1-w)

  y = 0.0d0
  y = y + x(1)  * (-u-v-1) * ( (1-u) * (1-v) - w + u*v*w * s ) / 4
  y = y + x(2)  * ( u-v-1) * ( (1+u) * (1-v) - w - u*v*w * s ) / 4
  y = y + x(3)  * ( u+v-1) * ( (1+u) * (1+v) - w + u*v*w * s ) / 4
  y = y + x(4)  * (-u+v-1) * ( (1-u) * (1+v) - w - u*v*w * s ) / 4
  y = y + x(5)  * w*(2*w-1)
  y = y + x(6)  * (1+u-w)*(1-u-w)*(1-v-w) * s / 2
  y = y + x(7)  * (1+v-w)*(1-v-w)*(1+u-w) * s / 2
  y = y + x(8)  * (1+u-w)*(1-u-w)*(1+v-w) * s / 2
  y = y + x(9)  * (1+v-w)*(1-v-w)*(1-u-w) * s / 2
  y = y + x(10) * w * (1-u-w) * (1-v-w) * s
  y = y + x(11) * w * (1+u-w) * (1-v-w) * s
  y = y + x(12) * w * (1+u-w) * (1+v-w) * s
  y = y + x(13) * w * (1-u-w) * (1+v-w) * s
  RETURN
END IF

      y = 0.0d0
      DO n = 1,elt % NumberOfNodes
        IF ( x(n) /= 0.0d0 ) THEN
          p => BasisFunctions(n) % p
          q => BasisFunctions(n) % q
          r => BasisFunctions(n) % r
          Coeff => BasisFunctions(n) % Coeff

          s = 0.0d0
          DO i = 1,BasisFunctions(n) % n
             s = s + Coeff(i) * u**p(i) * v**q(i) * w**r(i)
          END DO
          y = y + s*x(n)
        END IF
      END DO
!------------------------------------------------------------------------------
   END FUNCTION InterpolateInElement3D
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   FUNCTION FirstDerivativeInU3D( element,x,u,v,w ) RESULT(y)
DLLEXPORT FirstDerivativeInU3D
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!   Given element structure return value of the first partial derivative with
!   respect to local coordinate u of a quantity x given at element nodes at
!   local coordinate point u,v,w inside the element. Element basis functions
!   are used to compute the value. 
!
!  ARGUMENTS:
!   Type(Element_t) :: element
!     INPUT: element structure
!     
!    REAL(KIND=dp) :: x(:)
!     INPUT: Nodal values of the quantity whose partial derivative we want to know
!
!    REAL(KIND=dp) :: u,v,w
!     INPUT: Point at which to evaluate the partial derivative
!
!  FUNCTION VALUE:
!     REAL(KIND=dp) :: y
!      value of the quantity y = @x(u,v,w)/@u
!    
!******************************************************************************
   !
   ! Return first partial derivative in u of a quantity x at point u,v,w
   !

      Type(Element_t) :: element

      REAL(KIND=dp) :: u,v,w
      REAL(KIND=dp), DIMENSION(:) :: x

!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
      REAL(KIND=dp) :: y

      Type(ElementType_t),POINTER :: elt
      INTEGER :: i,j,k,l,n,m

      REAL(KIND=dp) :: s,t

      INTEGER, POINTER :: p(:),q(:), r(:)
      REAL(KIND=dp), POINTER :: Coeff(:)
      TYPE(BasisFunctions_t), POINTER :: BasisFunctions(:)
!------------------------------------------------------------------------------
      elt => element % Type
      l = elt % BasisFunctionDegree
      BasisFunctions => elt % BasisFunctions

IF ( Elt % ElementCode == 605 ) THEN
  IF ( w == 1 ) w = 1.0d0-1.0d-12
  s = 1.0d0 / (1-w)

  y = 0.0d0
  y = y + x(1) * ( -(1-v) + v*w * s ) / 4
  y = y + x(2) * (  (1-v) - v*w * s ) / 4
  y = y + x(3) * (  (1+v) + v*w * s ) / 4
  y = y + x(4) * ( -(1+v) - v*w * s ) / 4
  RETURN
ELSE IF ( Elt % ElementCode == 613 ) THEN
  IF ( w == 1 ) w = 1.0d0-1.0d-12
  s = 1.0d0 / (1-w)

  y = 0.0d0
  y = y + x(1)  * ( -( (1-u) * (1-v) - w + u*v*w * s ) + &
            (-u-v-1) * ( -(1-v) + v*w * s ) ) / 4

  y = y + x(2)  * (  ( (1+u) * (1-v) - w - u*v*w * s ) + &
            ( u-v-1) * (  (1-v) - v*w * s ) ) / 4

  y = y + x(3)  * (  ( (1+u) * (1+v) - w + u*v*w * s ) + &
            ( u+v-1) * (  (1+v) + v*w * s ) ) / 4

  y = y + x(4)  * ( -( (1-u) * (1+v) - w - u*v*w * s ) + &
            (-u+v-1) * ( -(1+v) - v*w * s ) ) / 4

  y = y + x(5)  * 0.0d0

  y = y + x(6)  * (  (1-u-w)*(1-v-w) - (1+u-w)*(1-v-w) ) * s / 2
  y = y + x(7)  * (  (1+v-w)*(1-v-w) ) * s / 2
  y = y + x(8)  * (  (1-u-w)*(1+v-w) - (1+u-w)*(1+v-w) ) * s / 2
  y = y + x(9)  * ( -(1+v-w)*(1-v-w) ) * s / 2

  y = y - x(10) * w * (1-v-w) * s
  y = y + x(11) * w * (1-v-w) * s
  y = y + x(12) * w * (1+v-w) * s
  y = y - x(13) * w * (1+v-w) * s

  RETURN
END IF

      y = 0.0d0
      DO n = 1,elt % NumberOfNodes
        IF ( x(n) /= 0.0d0 ) THEN
          p => BasisFunctions(n) % p
          q => BasisFunctions(n) % q
          r => BasisFunctions(n) % r
          Coeff => BasisFunctions(n) % Coeff

          s = 0.0d0
          DO i = 1,BasisFunctions(n) % n
             IF ( p(i) >= 1  ) THEN
                s = s + p(i) * Coeff(i) * u**(p(i)-1) * v**q(i) * w**r(i)
             END IF
          END DO
          y = y + s*x(n)
        END IF
      END DO
!------------------------------------------------------------------------------
   END FUNCTION FirstDerivativeInU3D
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   FUNCTION FirstDerivativeInV3D( element,x,u,v,w ) RESULT(y)
DLLEXPORT FirstDerivativeInV3D
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!   Given element structure return value of the first partial derivative with
!   respect to local coordinate v of a quantity x given at element nodes at
!   local coordinate point u,v,w inside the element. Element basis functions
!   are used to compute the value. 
!
!  ARGUMENTS:
!   Type(Element_t) :: element
!     INPUT: element structure
!     
!    REAL(KIND=dp) :: x(:)
!     INPUT: Nodal values of the quantity whose partial derivative we want to know
!
!    REAL(KIND=dp) :: u,v,w
!     INPUT: Point at which to evaluate the partial derivative
!
!  FUNCTION VALUE:
!     REAL(KIND=dp) :: y
!      value of the quantity y = @x(u,v,w)/@v
!    
!******************************************************************************
   !
   ! Return first partial derivative in v of a quantity x at point u,v,w
   !

      Type(Element_t) :: element

      REAL(KIND=dp) :: u,v,w
      REAL(KIND=dp), DIMENSION(:) :: x

!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
      REAL(KIND=dp) :: y

      Type(ElementType_t),POINTER :: elt

      INTEGER :: i,j,k,l,n,m

      REAL(KIND=dp) :: s,t

      INTEGER, POINTER :: p(:),q(:), r(:)
      REAL(KIND=dp), POINTER :: Coeff(:)
      TYPE(BasisFunctions_t), POINTER :: BasisFunctions(:)
!------------------------------------------------------------------------------
      elt => element % Type
      l = elt % BasisFunctionDegree
      BasisFunctions => elt % BasisFunctions

IF ( Elt % ElementCode == 605 ) THEN
  IF ( w == 1 ) w = 1.0d0-1.0d-12
  s = 1.0d0 / (1-w)

  y = 0.0d0
  y = y + x(1) * ( -(1-u) + u*w * s ) / 4
  y = y + x(2) * ( -(1+u) - u*w * s ) / 4
  y = y + x(3) * (  (1+u) + u*w * s ) / 4
  y = y + x(4) * (  (1-u) - u*w * s ) / 4

  RETURN
ELSE IF ( Elt % ElementCode == 613 ) THEN
  IF ( w == 1 ) w = 1.0d0-1.0d-12
  s = 1.0d0 / (1-w)

  y = 0.0d0
  y = y + x(1)  * ( -( (1-u) * (1-v) - w + u*v*w * s ) +  &
           (-u-v-1) * ( -(1-u) + u*w * s ) ) / 4

  y = y + x(2)  * ( -( (1+u) * (1-v) - w - u*v*w * s ) + &
           ( u-v-1) * ( -(1+u) - u*w * s ) ) / 4

  y = y + x(3)  * (  ( (1+u) * (1+v) - w + u*v*w * s ) + &
           ( u+v-1) * (  (1+u) + u*w * s ) ) / 4

  y = y + x(4)  * (  ( (1-u) * (1+v) - w - u*v*w * s ) + &
           (-u+v-1) * (  (1-u) - u*w * s ) ) / 4

  y = y + x(5)  * 0.0d0

  y = y - x(6)  *  (1+u-w)*(1-u-w) * s / 2
  y = y + x(7)  * ( (1-v-w)*(1+u-w) - (1+v-w)*(1+u-w) ) * s / 2
  y = y + x(8)  *  (1+u-w)*(1-u-w) * s / 2
  y = y + x(9)  * ( (1-v-w)*(1-u-w) - (1+v-w)*(1-u-w) ) * s / 2

  y = y - x(10) *  w * (1-u-w) * s
  y = y - x(11) *  w * (1+u-w) * s
  y = y + x(12) *  w * (1+u-w) * s
  y = y + x(13) *  w * (1-u-w) * s
  RETURN
END IF

      y = 0.0d0
      DO n = 1,elt % NumberOfNodes
        IF ( x(n) /= 0.0d0 ) THEN
          p => BasisFunctions(n) % p
          q => BasisFunctions(n) % q
          r => BasisFunctions(n) % r
          Coeff => BasisFunctions(n) % Coeff

          s = 0.0d0
          DO i = 1,BasisFunctions(n) % n
             IF ( q(i) >= 1  ) THEN
                s = s + q(i) * Coeff(i) * u**p(i) * v**(q(i)-1) * w**r(i)
             END IF
          END DO
          y = y + s*x(n)
        END IF
      END DO
   END FUNCTION FirstDerivativeInV3D
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   FUNCTION FirstDerivativeInW3D( element,x,u,v,w ) RESULT(y)
DLLEXPORT FirstDerivativeInW3D
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!   Given element structure return value of the first partial derivatives with
!   respect to local coordinate w of a quantity x given at element nodes at
!   local coordinate point u,v,w inside the element. Element basis functions
!   are used to compute the value. 
!
!  ARGUMENTS:
!   Type(Element_t) :: element
!     INPUT: element structure
!     
!    REAL(KIND=dp) :: x(:)
!     INPUT: Nodal values of the quantity whose partial derivative we want to know
!
!    REAL(KIND=dp) :: u,v,w
!     INPUT: Point at which to evaluate the partial derivative
!
!  FUNCTION VALUE:
!     REAL(KIND=dp) :: y
!      value of the quantity y = @x(u,v,w)/@w
!    
!******************************************************************************
   !
   ! Return first partial derivative in u of a quantity x at point u,v,w
   !
   !

      Type(Element_t) :: element

      REAL(KIND=dp) :: u,v,w
      REAL(KIND=dp), DIMENSION(:) :: x

!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
      REAL(KIND=dp) :: y

      Type(ElementType_t),POINTER :: elt
      INTEGER :: i,j,k,l,n,m

      REAL(KIND=dp) :: s,t

      INTEGER, POINTER :: p(:),q(:), r(:)
      REAL(KIND=dp), POINTER :: Coeff(:)
      TYPE(BasisFunctions_t), POINTER :: BasisFunctions(:)
!------------------------------------------------------------------------------
      elt => element % Type
      l = elt % BasisFunctionDegree
      BasisFunctions => elt % BasisFunctions

IF ( Elt % ElementCode == 605 ) THEN
  IF ( w == 1 ) w = 1.0d0-1.0d-12
  s = 1.0d0 / (1-w)

  y = 0.0d0
  y = y + x(1) * ( -1 + u*v*(2-w) * s**2 ) / 4
  y = y + x(2) * ( -1 - u*v*(2-w) * s**2 ) / 4
  y = y + x(3) * ( -1 + u*v*(2-w) * s**2 ) / 4
  y = y + x(4) * ( -1 - u*v*(2-w) * s**2 ) / 4
  y = y + x(5)
  RETURN
ELSE IF ( Elt % ElementCode == 613 ) THEN
  IF ( w == 1 ) w = 1.0d0-1.0d-12
  s = 1.0d0 / (1-w)

  y = 0.0d0
  y = y + x(1)  * (-u-v-1) * ( -1 + u*v*s**2 ) / 4
  y = y + x(2)  * ( u-v-1) * ( -1 - u*v*s**2 ) / 4
  y = y + x(3)  * ( u+v-1) * ( -1 + u*v*s**2 ) / 4
  y = y + x(4)  * (-u+v-1) * ( -1 - u*v*s**2 ) / 4

  y = y + x(5)  * (4*w-1)

  y = y + x(6)  * ( ( -(1-u-w)*(1-v-w) - (1+u-w)*(1-v-w) - (1+u-w)*(1-u-w) ) * s + &
                    ( 1+u-w)*(1-u-w)*(1-v-w) * s**2 ) / 2

  y = y + x(7)  * ( ( -(1-v-w)*(1+u-w) - (1+v-w)*(1+u-w) - (1+v-w)*(1-v-w) ) * s + &
                    ( 1+v-w)*(1-v-w)*(1+u-w) * s**2 ) / 2

  y = y + x(8)  * ( ( -(1-u-w)*(1+v-w) - (1+u-w)*(1+v-w) - (1+u-w)*(1-u-w) ) * s + &
                    ( 1+u-w)*(1-u-w)*(1+v-w) * s**2 ) / 2

  y = y + x(9)  * ( ( -(1-v-w)*(1-u-w) - (1+v-w)*(1-u-w) - (1+v-w)*(1-v-w) ) * s + &
                    ( 1+v-w)*(1-v-w)*(1-u-w) * s**2 ) / 2
                    
  y = y + x(10) * ( ( (1-u-w) * (1-v-w) - w * (1-v-w) - w * (1-u-w) ) * s  + &
                   w * (1-u-w) * (1-v-w) * s**2 )

  y = y + x(11) * ( ( (1+u-w) * (1-v-w) - w * (1-v-w) - w * (1+u-w) ) * s  + &
                   w * (1+u-w) * (1-v-w) * s**2 )

  y = y + x(12) * ( ( (1+u-w) * (1+v-w) - w * (1+v-w) - w * (1+u-w) ) * s  + &
                   w * (1+u-w) * (1+v-w) * s**2 )

  y = y + x(13) * ( ( (1-u-w) * (1+v-w) - w * (1+v-w) - w * (1-u-w) ) * s  + &
                   w * (1-u-w) * (1+v-w) * s**2 )
 RETURN
END IF

      y = 0.0d0
      DO n = 1,elt % NumberOfNodes
        IF ( x(n) /= 0.0d0 ) THEN
          p => BasisFunctions(n) % p
          q => BasisFunctions(n) % q
          r => BasisFunctions(n) % r
          Coeff => BasisFunctions(n) % Coeff

          s = 0.0d0
          DO i = 1,BasisFunctions(n) % n
             IF ( r(i) >= 1  ) THEN
                s = s + r(i) * Coeff(i) * u**p(i) * v**q(i) * w**(r(i)-1)
             END IF
          END DO
          y = y + s*x(n)
        END IF
      END DO
!------------------------------------------------------------------------------
   END FUNCTION FirstDerivativeInW3D
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   FUNCTION SecondDerivatives3D( element,x,u,v,w ) RESULT(ddx)
DLLEXPORT SecondDerivatives3D
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!   Given element structure return value of the second partial derivatives with
!   respect to local coordinates of i quantity x given at element nodes at local
!   coordinate point u,v inside the element. Element basis functions are used to
!   compute the value. 
!
!  ARGUMENTS:
!   Type(Element_t) :: element
!     INPUT: element structure
!     
!    REAL(KIND=dp) :: x(:)
!     INPUT: Nodal values of the quantity whose partial derivatives we want to know
!
!    REAL(KIND=dp) :: u,v
!     INPUT: Point at which to evaluate the partial derivative
!
!  FUNCTION VALUE:
!     REAL(KIND=dp) :: s
!      value of the quantity s = @^2x(u,v)/@v^2
!    
!******************************************************************************
   !
   !  Return matrix of second partial derivatives.
   !
!------------------------------------------------------------------------------

      Type(Element_t) :: element

      REAL(KIND=dp), DIMENSION(:) :: x
      REAL(KIND=dp) :: u,v,w

!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
      Type(ElementType_t),POINTER :: elt
      REAL(KIND=dp), DIMENSION (3,3) :: ddx
      TYPE(BasisFunctions_t), POINTER :: BasisFunctions(:)

      REAL(KIND=dp), POINTER :: Coeff(:)
      INTEGER, POINTER :: p(:), q(:), r(:)

      REAL(KIND=dp) :: s
      INTEGER :: i,j,k,l,n,m

!------------------------------------------------------------------------------
      elt => element % Type
      k = elt % NumberOfNodes
      BasisFunctions => elt % BasisFunctions

      ddx = 0.0d0

      DO n = 1,k
        IF ( x(n) /= 0.0d0 ) THEN
          p => elt % BasisFunctions(n) % p
          q => elt % BasisFunctions(n) % q
          r => elt % BasisFunctions(n) % r
          Coeff => elt % BasisFunctions(n) % Coeff
!------------------------------------------------------------------------------
!         @^2x/@u^2
!------------------------------------------------------------------------------
          s = 0.0d0
          DO i = 1,BasisFunctions(n) % n
             IF ( p(i) >= 2 ) THEN
                s = s + p(i) * (p(i)-1) * Coeff(i) * u**(p(i)-2) * v**q(i) * w**r(i)
             END IF
          END DO
          ddx(1,1) = ddx(1,1) + s*x(n)

!------------------------------------------------------------------------------
!         @^2x/@u@v
!------------------------------------------------------------------------------
          s = 0.0d0
          DO i = 1,BasisFunctions(n) % n
              IF (  p(i) >= 1 .AND. q(i) >= 1 ) THEN
                 s = s + p(i) * q(i) * Coeff(i) * u**(p(i)-1) * v**(q(i)-1) * w**r(i)
              END IF
          END DO
          ddx(1,2) = ddx(1,2) + s*x(n)

!------------------------------------------------------------------------------
!         @^2x/@u@w
!------------------------------------------------------------------------------
          s = 0.0d0
          DO i = 2,k
              IF (  p(i) >= 1 .AND. r(i) >= 1 ) THEN
                 s = s + p(i) * r(i) * Coeff(i) * u**(p(i)-1) * v**q(i) * w**(r(i)-1)
              END IF
          END DO
          ddx(1,3) = ddx(1,3) + s*x(n)

!------------------------------------------------------------------------------
!         @^2x/@v^2
!------------------------------------------------------------------------------
          s = 0.0d0
          DO i = 1,BasisFunctions(n) % n
             IF ( q(i) >= 2 ) THEN
                s = s + q(i) * (q(i)-1) * Coeff(i) * u**p(i) * v**(q(i)-2) * w**r(i)
             END IF
          END DO
          ddx(2,2) = ddx(2,2) + s*x(n)

!------------------------------------------------------------------------------
!         @^2x/@v@w
!------------------------------------------------------------------------------
          s = 0.0d0
          DO i = 1,BasisFunctions(n) % n
              IF (  q(i) >= 1 .AND. r(i) >= 1 ) THEN
                 s = s + q(i) * r(i) * Coeff(i) * u**p(i) * v**(q(i)-1) * w**(r(i)-1)
              END IF
          END DO
          ddx(2,3) = ddx(2,3) + s*x(n)

!------------------------------------------------------------------------------
!         @^2x/@w^2
!------------------------------------------------------------------------------
          s = 0.0d0
          DO i = 1,BasisFunctions(n) % n
             IF ( r(i) >= 2 ) THEN
                s = s + r(i) * (r(i)-1) * Coeff(i) * u**p(i) * v**q(i) * w**(r(i)-2)
             END IF
          END DO
          ddx(3,3) = ddx(3,3) + s*x(n)

        END IF
      END DO

      ddx(2,1) = ddx(1,2)
      ddx(3,1) = ddx(1,3)
      ddx(3,2) = ddx(2,3)

   END FUNCTION SecondDerivatives3D
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
   RECURSIVE FUNCTION ElementInfo( Element,Nodes,u,v,w,SqrtElementMetric, &
     Basis,dBasisdx,ddBasisddx,SecondDerivatives,Bubbles ) RESULT(stat)
DLLEXPORT ElementInfo
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!   
!  Return basis function values, basis function global first and, if requested,
!  second derivatives at given point in local coordinates.Also return square root
!  of element coordinate system metrics determinant (=sqrt(det(J^TJ))).
!
! ARGUMENTS:
!  Type(Element_t) :: element
!    INPUT: element structure
!     
!  Type(Nodes_t) :: Nodes
!    INPUT: element nodal coordinates
!
!  REAL(KIND=dp) :: u,v,w
!    INPUT: Point at which to evaluate the basis functions
!
!  REAL(KIND=dp) :: SqrtElementMetric
!    OUTPUT: Square root of determinant of element coordinate
!            system metric
!
!  REAL(KIND=dp) :: Basis(:)
!    OUTPUT: Basis function values at (u,v,w)
!
!  REAL(KIND=dp) :: dBasisdx(:,:)
!    OUTPUT: Global first derivatives of basis functions at (u,v,w)
!
!  REAL(KIND=dp) :: ddBasisddx(:,:)
!    OUTPUT: Global second derivatives of basis functions at (u,v,w),
!            if requested
!
!  LOGICAL :: SecondDerivatives
!    INPUT:  Are the second derivatives needed ?
!
!  INTEGER, OPTIONAL :: BasisDegree
!    INPUT:  Degree of each basis function in Basis(:) vector. May be used with
!            P element basis functions
!
! FUNCTION VALUE:
!    LOGICAL :: stat
!      If .FALSE. element is degenerate.
!   
!******************************************************************************
!------------------------------------------------------------------------------
     IMPLICIT NONE

     Type(Element_t), TARGET :: Element
     Type(Nodes_t)   :: Nodes
     REAL(KIND=dp) :: u,v,w,SqrtElementMetric
     REAL(KIND=dp) :: Basis(:),dBasisdx(:,:),ddBasisddx(:,:,:)
!    INTEGER, OPTIONAL :: BasisDegree(:)
     LOGICAL, OPTIONAL :: SecondDerivatives, Bubbles

!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------

     REAL(KIND=dp) :: NodalBasis(MAX_NODES),dLBasisdx(MAX_NODES,3), & 
                      BubbleValue, dBubbledx(3), t, s, ds, pTest, LtoGMap(3,3)
     LOGICAL :: invert, inverti, invertj, degrees
     INTEGER :: i,j,k,l,q,p,n,nb,dim,cdim,f, locali, localj, localMin, localPrev, &
          edge1, edge2, tmp(4), ii, jj, direction(4), BasisDegree(16)
     REAL(KIND=dp) :: detJ,LinBasis(16),dLinBasisdx(16,3),ElmMetric(3,3)

     Type(Element_t) :: Bubble
     TYPE(Element_t), POINTER :: Edge, Face

     LOGICAL :: stat
!------------------------------------------------------------------------------
     n    = Element % Type % NumberOfNodes
     dim  = Element % Type % Dimension
     cdim = CoordinateSystemDimension()

     IF ( Element % Type % ElementCode == 101 ) THEN
        Basis(1)      = 1
        dBasisdx(1,1) = 0
        dBasisdx(1,2) = 0
        dBasisdx(1,3) = 0
        SqrtElementMetric = 1
        RETURN
     END IF

     NodalBasis = 0.0d0
!------------------------------------------------------------------------------
!    Basis function derivatives with respect to local coordinates
!------------------------------------------------------------------------------
     DO q=1,N
        NodalBasis(q) = 1.0d0
        dLBasisdx(q,:) = 0.0d0
        SELECT CASE(dim)
        CASE (1)
           dLBasisdx(q,1) = FirstDerivative1D( element,NodalBasis,u )
        CASE (2)
           ! For triangles with p elements reference element is different so the 
           ! derivatives are different
           IF (isPTriangle(Element)) THEN
              dLBasisdx(q,1:2) = dTriangleNodalPBasis(q, u, v)
           ELSE 
              dLBasisdx(q,1) = FirstDerivativeInU2D( element,NodalBasis,u,v )
              dLBasisdx(q,2) = FirstDerivativeInV2D( element,NodalBasis,u,v )
           END IF
        CASE (3)
           ! For tetras, wedges and pyramids with p elements reference element
           ! is different than normal one used in Elmer 
           IF (isPTetra( Element )) THEN
              dLBasisdx(q,1:3) = dTetraNodalPBasis(q, u, v, w)
           ELSE IF (isPWedge( Element )) THEN
              dLBasisdx(q,1:3) = dWedgeNodalPBasis(q, u, v, w)
           ELSE IF (isPPyramid( Element )) THEN
              dLBasisdx(q,1:3) = dPyramidNodalPBasis(q, u, v, w)
           ELSE
              dLBasisdx(q,1) = FirstDerivativeInU3D( element,NodalBasis,u,v,w )
              dLBasisdx(q,2) = FirstDerivativeInV3D( element,NodalBasis,u,v,w )
              dLBasisdx(q,3) = FirstDerivativeInW3D( element,NodalBasis,u,v,w )
           END IF
        END SELECT
        NodalBasis(q) = 0.0d0
     END DO

!------------------------------------------------------------------------------
!    Element (contravariant) metric and square root of determinant
!------------------------------------------------------------------------------
     stat = ElementMetric(Element,Nodes,ElmMetric,SqrtElementMetric,dLBasisdx,LtoGMap)
!------------------------------------------------------------------------------
!    If degenerate element, dont even try it...
!------------------------------------------------------------------------------
     IF ( .NOT.stat ) RETURN

!------------------------------------------------------------------------------
!    Basis function values and global derivatives
!------------------------------------------------------------------------------
     dBasisdx = 0.0d0
     DO q=1,N
       NodalBasis(q) = 1.0d0
       SELECT CASE(dim)
         CASE (1)
            Basis(q) = InterpolateInElement1D( element,NodalBasis,u )
         CASE (2)
            IF (isPTriangle(Element)) THEN
               Basis(q) = TriangleNodalPBasis(q,u,v)
            ELSE 
               Basis(q) = InterpolateInElement2D( element,NodalBasis,u,v )
            END IF
         CASE (3)
            IF (isPTetra( Element )) THEN
               Basis(q) = TetraNodalPBasis(q,u,v,w)
            ELSE IF (isPWedge( Element )) THEN
               Basis(q) = WedgeNodalPBasis(q,u,v,w)
            ELSE IF (isPPyramid( Element )) THEN
               Basis(q) = PyramidNodalPBasis(q,u,v,w)
            ELSE
               Basis(q) = InterpolateInElement3D( element,NodalBasis,u,v,w )
            END IF
       END SELECT
       NodalBasis(q) = 0.0d0
     END DO

     q = n

     ! P ELEMENT CODE:
     ! ---------------
     IF (ASSOCIATED(Element % PDefs) ) THEN

      ! Check for need of P basis degrees and set degree of
      ! linear basis if vector asked:
      ! ---------------------------------------------------
      degrees = .FALSE.

      ! IF (PRESENT(BasisDegree)) THEN 
      !    degrees = .TRUE.
      !    BasisDegree = 0
      !    BasisDegree(1:Element % Type % NumberOfNodes) = 1
      ! END IF

!------------------------------------------------------------------------------
     SELECT CASE( Element % Type % ElementCode ) 
!------------------------------------------------------------------------------

     ! P element code for line element:
     ! --------------------------------
     CASE(202)
        ! Bubbles of line element
        IF (Element % BDOFs > 0) THEN
           ! For boundary element integration check direction
           invert = .FALSE.
           IF ( Element % PDefs % isEdge .AND. &
                Element % NodeIndexes(1) > Element % NodeIndexes(2) ) invert = .TRUE.

           ! For each bubble in line element get value of basis function
           DO i=1, Element % BDOFs
              q = q + 1
              IF (q > SIZE(Basis)) THEN
!                WRITE (*,*) 'Not enough space reserved for line p basis'
                 CYCLE
              END IF
              
              Basis(q) = LineBubblePBasis(i+1,u,invert)
              dLBasisdx(q,:) = 0
              dLBasisdx(q,1:1) = dLineBubblePBasis(i+1,u,invert)
              
              ! Polynomial degree of basis function to vector
              IF (degrees) BasisDegree(q) = 1+i
           END DO
        END IF

!------------------------------------------------------------------------------
! P element code for edges and bubbles of triangle
     CASE(303,306)
        ! Edges of triangle
        IF ( ASSOCIATED( Element % EdgeIndexes ) ) THEN
           ! For each edge calculate the value of edge basis function
           DO i=1,3
              Edge => CurrentModel % Solver % Mesh % Edges( Element % EdgeIndexes(i) )

              ! Get local number of edge start and endpoint nodes
              tmp(1:2) = getTriangleEdgeMap(i)
              locali = tmp(1)
              localj = tmp(2)

              ! Invert edge for parity if needed
              invert = .FALSE.
              IF ( Element % NodeIndexes(locali) > Element % NodeIndexes(localj) ) invert = .TRUE.
                            
              ! For each dof in edge get value of p basis function 
              DO k=1,Edge % BDOFs
                 q = q + 1
                 IF (q > SIZE(Basis)) THEN
!                   WRITE (*,*) 'Not enough space reserved for edge p basis'
                    CYCLE
                 END IF
                 
                 ! Value of basis functions for edge=i and i=k+1 by parity
                 Basis(q) = TriangleEdgePBasis(i, k+1, u, v, invert)
                 ! Value of derivative of basis function
                 dLBasisdx(q,:) = 0
                 dLBasisdx(q,1:2) = dTriangleEdgePBasis(i, k+1, u, v, invert)
                 
                 ! Polynomial degree of basis function to vector
                 IF (degrees) BasisDegree(q) = 1+k
              END DO
           END DO 
        END IF

        ! Bubbles of p triangle      
        IF ( Element % BDOFs > 0 ) THEN
           ! Get element p
           p = Element % PDefs % P

           nb = MAX( GetBubbleDOFs( Element, p ), Element % BDOFs )
           p = NINT( ( 3.0d0+SQRT(1.0d0+8.0d0*nb) ) / 2.0d0 )
           
           ! For boundary element direction needs to be calculated
           IF (Element % PDefs % isEdge) THEN
              direction = 0
              ! Get direction of this face (mask for face = boundary element nodes)
              direction(1:3) = getTriangleFaceDirection(Element, (/ 1,2,3 /))
           END IF

           DO i = 0,p-3
              DO j = 0,p-i-3
                 q = q + 1
                 
                 IF ( q > SIZE(Basis)  ) THEN
!                   WRITE (*,*) 'Not enough space reserved for triangle bubble p basis'
                    CYCLE
                 END IF

                 ! Get bubble basis functions and their derivatives
                 ! 3d Boundary element has a direction
                 IF (Element % PDefs % isEdge) THEN
                    Basis(q) = TriangleEBubblePBasis(i,j,u,v,direction) 
                    dLBasisdx(q,:)=0
                    dLBasisdx(q,1:2) = dTriangleEBubblePBasis(i,j,u,v,direction)
                 ELSE
                 ! 2d element bubbles have no direction
                    Basis(q) = TriangleBubblePBasis(i,j,u,v) 
                    dLBasisdx(q,:)=0
                    dLBasisdx(q,1:2) = dTriangleBubblePBasis(i,j,u,v)
                 END IF
                 
                 ! Polynomial degree of basis function to vector
                 IF (degrees) BasisDegree(q) = 3+i+j
              END DO
           END DO
        END IF
!------------------------------------------------------------------------------
! P element code for quadrilateral edges and bubbles 
     CASE(404,408)
        ! Edges of p quadrilateral
        IF ( ASSOCIATED( Element % EdgeIndexes ) ) THEN
           ! For each edge begin node calculate values of edge functions 
           DO i=1,4
              Edge => CurrentModel % Solver % Mesh % Edges( Element % EdgeIndexes(i) )

              ! Choose correct parity by global edge dofs
              tmp(1:2) = getQuadEdgeMap(i)
              locali = tmp(1)
              localj = tmp(2)
              
              ! Invert parity if needed
              invert = .FALSE.
              IF (Element % NodeIndexes(locali) > Element % NodeIndexes(localj)) invert = .TRUE. 

              ! For each DOF in edge calculate value of p basis function
              DO k=1,Edge % BDOFs
                 q = q + 1
                 IF ( q > SIZE(Basis)  ) THEN
!                   WRITE (*,*) 'Not enough space reserved for edge p basis'
                    CYCLE
                 END IF

                 ! For pyramid square face edges use different basis
                 IF (Edge % PDefs % pyramidQuadEdge) THEN
                    Basis(q) = QuadPyraEdgePBasis(i,k+1,u,v,invert)
                    dLBasisdx(q,:) = 0
                    dLBasisdx(q,1:2) = dQuadPyraEdgePBasis(i,k+1,u,v,invert)
                 ! Normal case, use basis of quadrilateral
                 ELSE
                    ! Get values of basis functions for edge=i and i=k+1 by parity
                    Basis(q) = QuadEdgePBasis(i,k+1,u,v,invert)
                    ! Get value of derivatives of basis functions
                    dLBasisdx(q,:) = 0
                    dLBasisdx(q,1:2) = dQuadEdgePBasis(i,k+1,u,v,invert)
                 END IF
                 
                 ! Polynomial degree of basis function to vector
                 IF (degrees) BasisDegree(q) = 1+k
              END DO              
           END DO         
        END IF

        ! Bubbles of p quadrilateral
        IF ( Element % BDOFs > 0 ) THEN
          ! Get element P
           p = Element % PDefs % P

           nb = MAX( GetBubbleDOFs( Element, p ), Element % BDOFs )
           p = NINT( ( 5.0d0+SQRT(1.0d0+8.0d0*nb) ) / 2.0d0 )

           ! For boundary element direction needs to be calculated
           IF (Element % PDefs % isEdge) THEN
              direction = 0
              direction = getSquareFaceDirection(Element, (/ 1,2,3,4 /))
           END IF
          
           ! For each bubble calculate value of p basis function
           ! and their derivatives for index pairs i,j>=2, i+j=4,...,p
           DO i=2,(p-2)
              DO j=2,(p-i)
                 q = q + 1
                 IF ( q > SIZE(Basis) .OR. q > SIZE(dBasisdx,1) ) THEN
!                   WRITE (*,*) 'Not enough space reserved for bubble p basis'
                    CYCLE
                 END IF
                 
                 ! Get values of bubble functions
                 ! 3D boundary elements have a direction
                 IF (Element % PDefs % isEdge) THEN
                    Basis(q) = QuadBubblePBasis(i,j,u,v,direction)
                    dLBasisdx(q,:) = 0
                    dLBasisdx(q,1:2) = dQuadBubblePBasis(i,j,u,v,direction)
                 ELSE
                 ! 2d element bubbles have no direction
                    Basis(q) = QuadBubblePBasis(i,j,u,v)
                    dLBasisdx(q,:) = 0
                    dLBasisdx(q,1:2) = dQuadBubblePBasis(i,j,u,v)
                 END IF

                 ! Polynomial degree of basis function to vector
                 IF (degrees) BasisDegree(q) = i+j
              END DO
           END DO
        END IF
!------------------------------------------------------------------------------
! P element code for tetrahedron edges, faces and bubbles
     CASE( 504 ) 
        ! Edges of p tetrahedron
        IF ( ASSOCIATED( Element % EdgeIndexes ) ) THEN   
           ! For each edge calculate value of edge functions
           DO i=1,6
              Edge => CurrentModel % Solver % Mesh % Edges (Element % EdgeIndexes(i))

              ! Do not solve edge DOFS if there is not any
              IF (Edge % BDOFs <= 0) CYCLE

              ! For each DOF in edge calculate value of edge functions 
              ! and their derivatives for edge=i, i=k+1
              DO k=1, Edge % BDOFs
                 q = q + 1
                 IF (q > SIZE(Basis)) THEN 
!                   WRITE (*,*) 'Not enough space reserved for tetra edge p basis'
                    CYCLE
                 END IF

                 Basis(q) = TetraEdgePBasis(i,k+1,u,v,w, Element % PDefs % TetraType)
                 dLBasisdx(q,:) = 0
                 dLBasisdx(q,1:3) = dTetraEdgePBasis(i,k+1,u,v,w, Element % PDefs % TetraType)

                 ! Polynomial degree of basis function to vector
                 IF (degrees) BasisDegree(q) = 1+k
              END DO
           END DO
        END IF

        ! Faces of p tetrahedron
        IF ( ASSOCIATED( Element % FaceIndexes )) THEN
           ! For each face calculate value of face functions
           DO F=1,4
              Face => CurrentModel % Solver % Mesh % Faces (Element % FaceIndexes(F))

              ! Do not solve face DOFs if there is not any
              IF (Face % BDOFs <= 0) CYCLE

              ! Get face p 
              p = Face % PDefs % P

              ! For each DOF in face calculate value of face functions and 
              ! their derivatives for face=F and index pairs 
              ! i,j=0,..,p-3, i+j=0,..,p-3
              DO i=0,p-3
                 DO j=0,p-i-3
                    q = q + 1 
                    
                    IF (q > SIZE(Basis)) THEN 
!                      WRITE (*,*) 'Not enough space reserved for tetra face p basis'
                       CYCLE
                    END IF
                    
                    Basis(q) = TetraFacePBasis(F,i,j,u,v,w, Element % PDefs % TetraType)
                    dLBasisdx(q,:) = 0
                    dLBasisdx(q,1:3) = dTetraFacePBasis(F,i,j,u,v,w, Element % PDefs % TetraType)

                    ! Polynomial degree of basis function to vector
                    IF (degrees) BasisDegree(q) = 3+i+j
                 END DO
              END DO
           END DO
        END IF

        ! Bubbles of p tetrahedron
        IF ( Element % BDOFs > 0 ) THEN
           p = Element % PDefs % P

           nb = MAX( GetBubbleDOFs(Element, p), Element % BDOFs )
           k = 81*nb + 3 * (729*nb**2 - 3)
           p = NINT( k**(1.0d0/3.0d0)/3.0d0 + 1.0d0/(k**(1.0d0/3.0d0)) + 2 )

           ! For each DOF in bubbles calculate value of bubble functions
           ! and their derivatives for index pairs
           ! i,j,k=0,..,p-4 i+j+k=0,..,p-4
           DO i=0,p-4
              DO j=0,p-i-4
                 DO k=0,p-i-j-4
                    q = q + 1
                    
                    IF (q > SIZE(Basis)) THEN
!                      WRITE (*,*) 'Not enough space reserved for tetra face p basis'
                       CYCLE
                    END IF

                    Basis(q) = TetraBubblePBasis(i,j,k,u,v,w)
                    dLBasisdx(q,:) = 0
                    dLBasisdx(q,1:3) = dTetraBubblePBasis(i,j,k,u,v,w)

                    ! Polynomial degree of basis function to vector
                    IF (degrees) BasisDegree(q) = 4+i+j+k
                 END DO
              END DO
           END DO
           
        END IF
!------------------------------------------------------------------------------
! P element code for pyramid edges, faces and bubbles
     CASE( 605 )
        ! Edges of P Pyramid
        IF (ASSOCIATED( Element % EdgeIndexes ) ) THEN
           ! For each edge in wedge, calculate values of edge functions
           DO i=1,8
              Edge => CurrentModel % Solver % Mesh % Edges( Element % EdgeIndexes(i) )

              ! Do not solve edge dofs, if there is not any
              IF (Edge % BDOFs <= 0) CYCLE
              
              ! Get local indexes of current edge
              tmp(1:2) = getPyramidEdgeMap(i)
              locali = tmp(1)
              localj = tmp(2)

              ! Determine edge direction
              invert = .FALSE.
              
              ! Invert edge if local first node has greater global index than second one
              IF ( Element % NodeIndexes(locali) > Element % NodeIndexes(localj) ) invert = .TRUE.

              ! For each DOF in edge calculate values of edge functions
              ! and their derivatives for edge=i and i=k+1
              DO k=1,Edge % BDOFs
                 q = q + 1
                 IF ( q > SIZE(Basis)  ) THEN
!                   WRITE (*,*) 'Not enough space reserved for pyramid edge p basis'
                    CYCLE
                 END IF

                 ! Get values of edge basis functions and their derivatives
                 dLBasisdx(q,:)  = 0
                 Basis(q) = PyramidEdgePBasis(i,k+1,u,v,w,invert)
                 dLBasisdx(q,1:3) = dPyramidEdgePBasis(i,k+1,u,v,w,invert)

                 ! Polynomial degree of basis function to vector
                 IF (degrees) BasisDegree(q) = 1+k
              END DO
           END DO
        END IF
        
        ! Faces of P Pyramid
        IF ( ASSOCIATED( Element % FaceIndexes ) ) THEN
           ! For each face in pyramid, calculate values of face functions
           DO F=1,5
              Face => CurrentModel % Solver % Mesh % Faces( Element % FaceIndexes(F) )

              ! Do not solve face dofs, if there is not any
              IF ( Face % BDOFs <= 0) CYCLE
              
              ! Get face p
              p = Face % PDefs % P 
              
              ! Handle triangle and square faces separately
              SELECT CASE(F)
              CASE (1)
                 direction = 0
                 ! Get global direction vector for enforcing parity
                 tmp(1:4) = getPyramidFaceMap(F)
                 direction(1:4) = getSquareFaceDirection( Element, tmp(1:4) )
                 
                 ! For each face calculate values of functions from index
                 ! pairs i,j=2,..,p-2 i+j=4,..,p
                 DO i=2,p-2
                    DO j=2,p-i
                       q = q + 1
                       
                       IF ( q > SIZE(Basis)  ) THEN
!                         WRITE (*,*) 'Not enough space reserved for pyramid face p basis'
                          CYCLE
                       END IF
                       
                       dLBasisdx(q,:) = 0
                       Basis(q) = PyramidFacePBasis(F,i,j,u,v,w,direction)
                       dLBasisdx(q,:) = dPyramidFacePBasis(F,i,j,u,v,w,direction)
                       
                       ! Polynomial degree of basis function to vector
                       IF (degrees) BasisDegree(q) = i+j
                    END DO
                 END DO

              CASE (2,3,4,5)
                 direction = 0
                 ! Get global direction vector for enforcing parity
                 tmp(1:4) = getPyramidFaceMap(F) 
                 direction(1:3) = getTriangleFaceDirection( Element, tmp(1:3) )
                 
                 ! For each face calculate values of functions from index
                 ! pairs i,j=0,..,p-3 i+j=0,..,p-3
                 DO i=0,p-3
                    DO j=0,p-i-3
                       q = q + 1
                       
                       IF ( q > SIZE(Basis)  ) THEN
!                         WRITE (*,*) 'Not enough space reserved for pyramid face p basis'
                          CYCLE
                       END IF

                       dLBasisdx(q,:) = 0
                       Basis(q) = PyramidFacePBasis(F,i,j,u,v,w,direction)
                       dLBasisdx(q,:) = dPyramidFacePBasis(F,i,j,u,v,w,direction)

                       ! Polynomial degree of basis function to vector
                       IF (degrees) BasisDegree(q) = 3+i+j
                    END DO
                 END DO
              END SELECT    
           END DO
        END IF

        ! Bubbles of P Pyramid
        IF (Element % BDOFs >= 0) THEN 
           ! Get element p
           p = Element % PDefs % p
           nb = MAX( GetBubbleDOFs(Element, p), Element % BDOFs )
           k = 81*nb + 3 * (729*nb**2 - 3)
           p = NINT( k**(1.0d0/3.0d0)/3.0d0 + 1.0d0/(k**(1.0d0/3.0d0)) + 2 )

           ! Calculate value of bubble functions from indexes
           ! i,j,k=0,..,p-4 i+j+k=0,..,p-4
           DO i=0,p-4
              DO j=0,p-i-4
                 DO k=0,p-i-j-4
                    q = q + 1
                    
                    IF ( q > SIZE(Basis)) THEN
!                      WRITE (*,*) 'Not enough space reserved for pyramid bubble p basis'
                       CYCLE
                    END IF

                    dLBasisdx(q,:) = 0
                    Basis(q) = PyramidBubblePBasis(i,j,k,u,v,w)
                    dLBasisdx(q,:) = dPyramidBubblePBasis(i,j,k,u,v,w)
                    
                    ! Polynomial degree of basis function to vector
                    IF (degrees) BasisDegree(q) = 4+i+j+k
                 END DO
              END DO
           END DO
        END IF
        
!------------------------------------------------------------------------------
! P element code for wedge edges, faces and bubbles
     CASE( 706 )
        ! Edges of P Wedge
        IF (ASSOCIATED( Element % EdgeIndexes ) ) THEN
           ! For each edge in wedge, calculate values of edge functions
           DO i=1,9
              Edge => CurrentModel % Solver % Mesh % Edges( Element % EdgeIndexes(i) )

              ! Do not solve edge dofs, if there is not any
              IF (Edge % BDOFs <= 0) CYCLE
              
              ! Get local indexes of current edge
              tmp(1:2) = getWedgeEdgeMap(i)
              locali = tmp(1)
              localj = tmp(2)

              ! Determine edge direction
              invert = .FALSE.
              ! Invert edge if local first node has greater global index than second one
              IF ( Element % NodeIndexes(locali) > Element % NodeIndexes(localj) ) invert = .TRUE.
       
              ! For each DOF in edge calculate values of edge functions
              ! and their derivatives for edge=i and i=k+1
              DO k=1,Edge % BDOFs
                 q = q + 1
                 IF ( q > SIZE(Basis)  ) THEN
!                   WRITE (*,*) 'Not enough space reserved for wedge edge p basis'
                    CYCLE
                 END IF

                 ! Use basis compatible with pyramid if neccessary
                 ! @todo Correct this!
                 IF (Edge % PDefs % pyramidQuadEdge) THEN
                    CALL Fatal('ElementInfo','Pyramid compatible wedge edge basis NIY!')
                 END IF

                 ! Get values of edge basis functions and their derivatives
                 dLBasisdx(q,:)  = 0
                 Basis(q) = WedgeEdgePBasis(i,k+1,u,v,w,invert)
                 dLBasisdx(q,1:3) = dWedgeEdgePBasis(i,k+1,u,v,w,invert)

                 ! Polynomial degree of basis function to vector
                 IF (degrees) BasisDegree(q) = 1+k
              END DO
           END DO
        END IF

        ! Faces of P Wedge 
        IF ( ASSOCIATED( Element % FaceIndexes ) ) THEN
           ! For each face in wedge, calculate values of face functions
           DO F=1,5
              Face => CurrentModel % Solver % Mesh % Faces( Element % FaceIndexes(F) )

              ! Do not solve face dofs, if there is not any
              IF ( Face % BDOFs <= 0) CYCLE

              p = Face % PDefs % P 
              
              ! Handle triangle and square faces separately
              SELECT CASE(F)
              CASE (1,2)
                 direction = 0
                 ! Get global direction vector for enforcing parity
                 tmp(1:4) = getWedgeFaceMap(F) 
                 direction(1:3) = getTriangleFaceDirection( Element, tmp(1:3) )
                 
                 ! For each face calculate values of functions from index
                 ! pairs i,j=0,..,p-3 i+j=0,..,p-3
                 DO i=0,p-3
                    DO j=0,p-i-3
                       q = q + 1
                       
                       IF ( q > SIZE(Basis)  ) THEN
!                         WRITE (*,*) 'Not enough space reserved for wedge face p basis'
                          CYCLE
                       END IF

                       dLBasisdx(q,:) = 0
                       Basis(q) = WedgeFacePBasis(F,i,j,u,v,w,direction)
                       dLBasisdx(q,:) = dWedgeFacePBasis(F,i,j,u,v,w,direction)

                       ! Polynomial degree of basis function to vector
                       IF (degrees) BasisDegree(q) = 3+i+j
                    END DO
                 END DO
              CASE (3,4,5)
                 direction = 0
                 ! Get global direction vector for enforcing parity
                 invert = .FALSE.
                 tmp(1:4) = getWedgeFaceMap(F)
                 direction(1:4) = getSquareFaceDirection( Element, tmp(1:4) )
                 
                 ! First and second node must form a face in upper or lower triangle
                 IF (.NOT. wedgeOrdering(direction)) THEN
                    invert = .TRUE.
                    tmp(1) = direction(2)
                    direction(2) = direction(4)
                    direction(4) = tmp(1)
                 END IF

                 ! For each face calculate values of functions from index
                 ! pairs i,j=2,..,p-2 i+j=4,..,p
                 DO i=2,p-2
                    DO j=2,p-i
                       q = q + 1
                       
                       IF ( q > SIZE(Basis)  ) THEN
!                         WRITE (*,*) 'Not enough space reserved for wedge face p basis'
                          CYCLE
                       END IF

                       dLBasisdx(q,:) = 0
                       IF (.NOT. invert) THEN
                          Basis(q) = WedgeFacePBasis(F,i,j,u,v,w,direction)
                          dLBasisdx(q,:) = dWedgeFacePBasis(F,i,j,u,v,w,direction)
                       ELSE
                          Basis(q) = WedgeFacePBasis(F,j,i,u,v,w,direction)
                          dLBasisdx(q,:) = dWedgeFacePBasis(F,j,i,u,v,w,direction)
                       END IF

                       ! Polynomial degree of basis function to vector
                       IF (degrees) BasisDegree(q) = i+j
                    END DO
                 END DO
              END SELECT
                           
           END DO
        END IF

        ! Bubbles of P Wedge
        IF ( Element % BDOFs > 0 ) THEN
           ! Get p from element
           p = Element % PDefs % P
           nb = MAX( GetBubbleDOFs( Element, p ), Element % BDOFs )
           k = 81*nb + 3*(729*nb**2 - 3)
           p = NINT( k**(1.0d0/3.0d0)/3.0d0 + 1.0d0/(k**(1.0d0/3.0d0)) + 3 )
           
           ! For each bubble calculate value of basis function and its derivative
           ! for index pairs i,j=0,..,p-5 k=2,..,p-3 i+j+k=2,..,p-3
           DO i=0,p-5
              DO j=0,p-5-i
                 DO k=2,p-3-i-j
                    q = q + 1
                    IF ( q > SIZE(Basis)  ) THEN
!                      WRITE (*,*) 'Not enough space reserved for wedge bubble p basis'
                       CYCLE
                    END IF

                    dLBasisdx(q,:) = 0
                    Basis(q) = WedgeBubblePBasis(i,j,k,u,v,w)
                    dLBasisdx(q,:) = dWedgeBubblePBasis(i,j,k,u,v,w)

                    ! Polynomial degree of basis function to vector
                    IF (degrees) BasisDegree(q) = 3+i+j+k
                 END DO
              END DO
           END DO
        END IF

!------------------------------------------------------------------------------
! P element code for brick edges, faces and bubbles
     CASE( 808 ) 
        ! Edges of P brick
        IF ( ASSOCIATED( Element % EdgeIndexes ) ) THEN
           ! For each edge in brick, calculate values of edge functions 
           DO i=1,12
              Edge => CurrentModel % Solver % Mesh % Edges( Element % EdgeIndexes(i) )

              ! Do not solve edge dofs, if there is not any
              IF (Edge % BDOFs <= 0) CYCLE
              
              ! Get local indexes of current edge
              tmp(1:2) = getBrickEdgeMap(i)
              locali = tmp(1)
              localj = tmp(2)
              
              ! Determine edge direction
              invert = .FALSE.
              
              ! Invert edge if local first node has greater global index than second one
              IF ( Element % NodeIndexes(locali) > Element % NodeIndexes(localj) ) invert = .TRUE.
              
              ! For each DOF in edge calculate values of edge functions
              ! and their derivatives for edge=i and i=k+1
              DO k=1,Edge % BDOFs
                 q = q + 1
                 IF ( q > SIZE(Basis)  ) THEN
!                   WRITE (*,*) 'Not enough space reserved for brick edge p basis'
                    CYCLE
                 END IF

                 ! For edges connected to pyramid square face, use different basis
                 IF (Edge % PDefs % pyramidQuadEdge) THEN
                    ! Get values of edge basis functions and their derivatives
                    dLBasisdx(q,:)  = 0
                    Basis(q) = BrickPyraEdgePBasis(i,k+1,u,v,w,invert)
                    dLBasisdx(q,1:3) = dBrickPyraEdgePBasis(i,k+1,u,v,w,invert)
                 ! Normal case. Use standard brick edge functions
                 ELSE
                    ! Get values of edge basis functions and their derivatives
                    dLBasisdx(q,:)  = 0
                    Basis(q) = BrickEdgePBasis(i,k+1,u,v,w,invert)
                    dLBasisdx(q,1:3) = dBrickEdgePBasis(i,k+1,u,v,w,invert)
                 END IF

                 ! Polynomial degree of basis function to vector
                 IF (degrees) BasisDegree(q) = 1+k
              END DO
           END DO 
        END IF

        ! Faces of P brick
        IF ( ASSOCIATED( Element % FaceIndexes ) ) THEN
           ! For each face in brick, calculate values of face functions
           DO F=1,6
              Face => CurrentModel % Solver % Mesh % Faces( Element % FaceIndexes(F) )
                          
              ! Do not calculate face values if no dofs
              IF (Face % BDOFs <= 0) CYCLE
              
              ! Get p for face
              p = Face % PDefs % P
              
              ! Generate direction vector for this face
              tmp(1:4) = getBrickFaceMap(F)
              direction(1:4) = getSquareFaceDirection(Element, tmp)
              
              ! For each face calculate values of functions from index
              ! pairs i,j=2,..,p-2 i+j=4,..,p
              DO i=2,p-2
                 DO j=2,p-i
                    q = q + 1

                    IF ( q > SIZE(Basis)  ) THEN
                       WRITE (*,*) 'Not enough space reserved for brick face p basis'
                       CYCLE
                    END IF

                    dLBasisdx(q,:) = 0
                    Basis(q) = BrickFacePBasis(F,i,j,u,v,w,direction)
                    dLBasisdx(q,:) = dBrickFacePBasis(F,i,j,u,v,w,direction)

                    ! Polynomial degree of basis function to vector
                    IF (degrees) BasisDegree(q) = i+j
                 END DO
              END DO
           END DO
        END IF

        ! Bubbles of p brick
        IF ( Element % BDOFs > 0 ) THEN
           ! Get p from bubble DOFs 
           p = Element % PDefs % P
           nb = MAX( GetBubbleDOFs(Element, p), Element % BDOFs )
           k = 81*nb + 3 * (729*nb**2 - 3)
           p = NINT( k**(1.0d0/3.0d0)/3.0d0 + 1.0d0/(k**(1.0d0/3.0d0)) + 3 )
           
           ! For each bubble calculate value of basis function and its derivative
           ! for index pairs i,j,k=2,..,p-4, i+j+k=6,..,p
           DO i=2,p-4
              DO j=2,p-i-2
                 DO k=2,p-i-j
                    q = q + 1
                    IF ( q > SIZE(Basis)  ) THEN
!                      WRITE (*,*) 'Not enough space reserved for brick bubble p basis'
                       CYCLE
                    END IF

                    dLBasisdx(q,:) = 0
                    Basis(q) = BrickBubblePBasis(i,j,k,u,v,w)
                    dLBasisdx(q,:) = dBrickBubblePBasis(i,j,k,u,v,w)

                    ! Polynomial degree of basis function to vector
                    IF (degrees) BasisDegree(q) = i+j+k
                 END DO
              END DO
           END DO
        END IF

     END SELECT
     END IF ! P element flag check
!------------------------------------------------------------------------------
     ! Get global first derivatives 
      dBasisdx(1:q,1:cdim) = MATMUL(dlBasisdx(1:q,1:dim), &
            TRANSPOSE(LtoGMap(1:cdim,1:dim)))

!------------------------------------------------------------------------------
!    Get matrix of second derivatives, if needed
!------------------------------------------------------------------------------
     IF ( SecondDerivatives ) THEN
       ddBasisddx(1:n,:,:) = 0.0d0
       DO q=1,N
         NodalBasis(q) = 1.0d0
         CALL GlobalSecondDerivatives(element,nodes,NodalBasis, &
             ddBasisddx(q,:,:),u,v,w,ElmMetric,dLBasisdx )
         NodalBasis(q) = 0.0d0
       END DO
     END IF

!------------------------------------------------------------------------------
!    Generate bubble basis functions, if requested. Bubble basis is as follows:
!    B_i (=(N_(i+n)) = B * N_i, where N_i:s are the nodal basis functions of
!    the element, and B the basic bubble, i.e. the product of nodal basis
!    functions of the corresponding linear element for triangles and tetras,
!    and product of two diagonally opposed nodal basisfunctions of the
!    correspoding (bi-,tri-)linear element for 1d-elements, quads and hexas.
!------------------------------------------------------------------------------
     IF ( PRESENT( Bubbles ) ) THEN
       Bubble % BDOFs = 0
       NULLIFY( Bubble % PDefs )
       NULLIFY( Bubble % EdgeIndexes )
       NULLIFY( Bubble % FaceIndexes )
       NULLIFY( Bubble % BubbleIndexes )

       IF ( Bubbles .AND. SIZE(Basis) >= 2*n ) THEN

         SELECT CASE(Element % Type % ElementCode / 100)
           CASE(2)

              IF ( Element % Type % ElementCode == 202 ) THEN
                LinBasis(1:n) = Basis(1:n)
                dLinBasisdx(1:n,1:cdim) = dBasisdx(1:n,1:cdim)
              ELSE
                Bubble % Type => GetElementType(202)

                stat = ElementInfo( Bubble, nodes, u, v, w, detJ, &
                  LinBasis, dLinBasisdx, ddBasisddx, .FALSE., .FALSE. )
              END IF

              BubbleValue = LinBasis(1) * LinBasis(2)

              DO i=1,n
                Basis(n+i) = Basis(i) * BubbleValue
                DO j=1,cdim
                  dBasisdx(n+i,j) = dBasisdx(i,j) * BubbleValue

                  dBasisdx(n+i,j) = dBasisdx(n+i,j) + Basis(i) * &
                       dLinBasisdx(1,j) * LinBasis(2)

                  dBasisdx(n+i,j) = dBasisdx(n+i,j) + Basis(i) * &
                       dLinBasisdx(2,j) * LinBasis(1)
                END DO
              END DO

           CASE(3)

              IF ( Element % Type % ElementCode == 303 ) THEN
                LinBasis(1:n) = Basis(1:n)
                dLinBasisdx(1:n,1:cdim) = dBasisdx(1:n,1:cdim)
              ELSE
                Bubble % Type => GetElementType(303)

                stat = ElementInfo( Bubble, nodes, u, v, w, detJ, &
                  LinBasis, dLinBasisdx, ddBasisddx, .FALSE., .FALSE. )
              END IF
  
              BubbleValue = LinBasis(1) * LinBasis(2) * LinBasis(3)

              DO i=1,n
                Basis(n+i) = Basis(i) * BubbleValue
                DO j=1,cdim
                  dBasisdx(n+i,j) = dBasisdx(i,j) * BubbleValue

                  dBasisdx(n+i,j) = dBasisdx(n+i,j) + Basis(i) * &
                       dLinBasisdx(1,j) * LinBasis(2) * LinBasis(3)

                  dBasisdx(n+i,j) = dBasisdx(n+i,j) + Basis(i) * &
                       dLinBasisdx(2,j) * LinBasis(1) * LinBasis(3)

                  dBasisdx(n+i,j) = dBasisdx(n+i,j) + Basis(i) * &
                       dLinBasisdx(3,j) * LinBasis(1) * LinBasis(2)
                END DO
              END DO

           CASE(4)

              IF ( Element % Type % ElementCode == 404 ) THEN
                LinBasis(1:n) = Basis(1:n)
                dLinBasisdx(1:n,1:cdim) = dBasisdx(1:n,1:cdim)
              ELSE
                Bubble % Type => GetElementType(404)

                stat = ElementInfo( Bubble, nodes, u, v, w, detJ, &
                  LinBasis, dLinBasisdx, ddBasisddx, .FALSE., .FALSE. )
              END IF

              BubbleValue = LinBasis(1) * LinBasis(3)

              DO i=1,n
                Basis(n+i) = Basis(i) * BubbleValue
                DO j=1,cdim
                  dBasisdx(n+i,j) = dBasisdx(i,j) * BubbleValue

                  dBasisdx(n+i,j) = dBasisdx(n+i,j) + Basis(i) * &
                         dLinBasisdx(1,j) * LinBasis(3)

                  dBasisdx(n+i,j) = dBasisdx(n+i,j) + Basis(i) * &
                         dLinBasisdx(3,j) * LinBasis(1)
                END DO
              END DO

           CASE(5)

              IF ( Element % Type % ElementCode == 504 ) THEN
                LinBasis(1:n) = Basis(1:n)
                dLinBasisdx(1:n,1:cdim) = dBasisdx(1:n,1:cdim)
              ELSE
                Bubble % Type => GetElementType(504)

                stat = ElementInfo( Bubble, nodes, u, v, w, detJ, &
                   LinBasis, dLinBasisdx, ddBasisddx, .FALSE., .FALSE. )
              END IF

              BubbleValue = LinBasis(1) * LinBasis(2) * LinBasis(3) * LinBasis(4)
              DO i=1,n
                Basis(n+i) = Basis(i) * BubbleValue
                DO j=1,cdim
                  dBasisdx(n+i,j) = dBasisdx(i,j) * BubbleValue

                  dBasisdx(n+i,j) = dBasisdx(n+i,j) + Basis(i) * dLinBasisdx(1,j) * &
                                    LinBasis(2) * LinBasis(3) * LinBasis(4)

                  dBasisdx(n+i,j) = dBasisdx(n+i,j) + Basis(i) * dLinBasisdx(2,j) * &
                                    LinBasis(1) * LinBasis(3) * LinBasis(4)

                  dBasisdx(n+i,j) = dBasisdx(n+i,j) + Basis(i) * dLinBasisdx(3,j) * &
                                    LinBasis(1) * LinBasis(2) * LinBasis(4)

                  dBasisdx(n+i,j) = dBasisdx(n+i,j) + Basis(i) * dLinBasisdx(4,j) * &
                                    LinBasis(1) * LinBasis(2) * LinBasis(3)
                END DO
              END DO
     
           CASE(8)

              IF ( Element % Type % ElementCode == 808 ) THEN
                LinBasis(1:n) = Basis(1:n)
                dLinBasisdx(1:n,1:cdim) = dBasisdx(1:n,1:cdim)
              ELSE
                Bubble % Type => GetElementType(808)

                stat = ElementInfo( Bubble, nodes, u, v, w, detJ, &
                  LinBasis, dLinBasisdx, ddBasisddx, .FALSE., .FALSE. )
              END IF

              BubbleValue = LinBasis(1) * LinBasis(7)

              DO i=1,n
                Basis(n+i) = Basis(i) * BubbleValue
                DO j=1,cdim
                  dBasisdx(n+i,j) = dBasisdx(i,j) * BubbleValue

                  dBasisdx(n+i,j) = dBasisdx(n+i,j) + Basis(i) * &
                        dLinBasisdx(1,j) * LinBasis(7)

                  dBasisdx(n+i,j) = dBasisdx(n+i,j) + Basis(i) * &
                        dLinBasisdx(7,j) * LinBasis(1)
                END DO
              END DO

         END SELECT
       END IF
     END IF
!------------------------------------------------------------------------------
   END FUNCTION ElementInfo
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   FUNCTION WhitneyElementInfo( Element,Basis,dBasisdx, &
      nedges, WhitneyBasis,dWhitneyBasisdx ) RESULT(stat)
DLLEXPORT WhitneyElementInfo
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!   
!  Returns Whitney basis vector functions (edge elements W1 in 3D) values
!  and Whitney basis function global first derivatives at given point in
!  local coordinates.
!
! ARGUMENTS:
!  Type(Element_t) :: element
!    INPUT: element structure
!     
!  REAL(KIND=dp) :: u,v,w
!    INPUT: Point at which to evaluate the basis functions
!
!  REAL(KIND=dp) :: Basis(:)
!    INPUT: Barycentric basis function (#nodes) values at (u,v,w)
!
!  REAL(KIND=dp) :: WhitneyBasis(:,:)
!    OUTPUT: Basis vector function (#edges,3) values at (u,v,w)
!
!  REAL(KIND=dp) :: dWhitneyBasisdx(:,:,:)
!    OUTPUT: Global first derivatives of basis functions at (u,v,w)
!
! FUNCTION VALUE:
!    LOGICAL :: stat
!      If .FALSE. element is degenerate or not a Whitney element
!   
!******************************************************************************
!------------------------------------------------------------------------------

     Type(Element_t) :: Element

     REAL(KIND=dp) :: Basis(:),dBasisdx(:,:),WhitneyBasis(:,:),dWhitneyBasisdx(:,:,:)
     INTEGER :: nedges
     LOGICAL :: stat
!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------

     INTEGER :: i,j,k,l,q,n,dim,cdim

!------------------------------------------------------------------------------

     n    = Element % Type % NumberOfNodes
     dim  = Element % Type % Dimension
     cdim = CoordinateSystemDimension()

     IF ( (dim /= 3) .OR. (cdim /= 3 ) ) THEN
       stat = .FALSE.
       CALL Error( 'WhitheyElementInfo', 'Whitney elements implemented only in 3D' )
       RETURN
     END IF

     nedges = 6 ! tetras, 12 for bricks

     DO q=1,nedges
! Find appropriate end nodes (i,j) for edge q
       IF (nedges == 6) THEN
! For tetras
         SELECT CASE (q)
           CASE(1)
           i=1
           j=2
           CASE(2)
           i=2
           j=3
           CASE(3)
           i=3
           j=1
           CASE(4)
           i=4
           j=1
           CASE(5)
           i=4
           j=2
           CASE(6)
           i=3
           j=4
         END SELECT
       ELSE
         IF (nedges == 12) THEN
! For bricks
           SELECT CASE (q)
             CASE(1)
             i=1
             j=2
             CASE(2)
             i=2
             j=3
             CASE(3)
             i=3
             j=4
             CASE(4)
             i=4
             j=1
             CASE(5)
             i=5
             j=6
             CASE(6)
             i=6
             j=7
             CASE(7)
             i=7
             j=8
             CASE(8)
             i=8
             j=5
             CASE(9)
             i=1
             j=5
             CASE(10)
             i=2
             j=6
             CASE(11)
             i=3
             j=7
             CASE(12)
             i=4
             j=8
           END SELECT
         ELSE
           CALL Fatal( 'WhitneyElementInfo', &
               'Not appropriate number of edges for Whitney elements' )
         END IF
       END IF

       IF (Element % NodeIndexes (i) < Element % NodeIndexes (j) ) THEN
         k = i
         i = j
         j = k
       END IF

       DO k=1, dim !or cdim=3, kth component of the basis function q
         WhitneyBasis(q,k) = Basis(i)*dBasisdx(j,k) &
             - Basis(j)*dBasisdx(i,k)
         DO l=1,dim
           dWhitneyBasisdx(q,k,l) = &
               dBasisdx(i,l)*dBasisdx(j,k) - dBasisdx(j,l)*dBasisdx(i,k)
         END DO
       END DO

     END DO
!------------------------------------------------------------------------------
   END FUNCTION WhitneyElementInfo
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   FUNCTION Whitney2ElementInfo( Element,Basis,dBasisdx, &
      nfaces, WhitneyBasis,dWhitneyBasisdx ) RESULT(stat)
DLLEXPORT WhitneyElementInfo
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!   
!  Returns Whitney basis vector functions (face elements W2 in 3D) values
!  and Whitney basis function global first derivatives at given point in
!  local coordinates.
!
! ARGUMENTS:
!  Type(Element_t) :: element
!    INPUT: element structure
!
!  Type(Nodes_t) :: Nodes
!    INPUT: element nodal coordinates
!     
!  REAL(KIND=dp) :: u,v,w
!    INPUT: Point at which to evaluate the basis functions
!
!  REAL(KIND=dp) :: Basis(:)
!    INPUT: Barycentric basis function (#nodes) values at (u,v,w)
!
!  REAL(KIND=dp) :: WhitneyBasis(:,:)
!    OUTPUT: Basis vector function (#faces,3) values at (u,v,w)
!
!  REAL(KIND=dp) :: dWhitneyBasisdx(:,:,:)
!    OUTPUT: Global first derivatives of basis functions at (u,v,w)
!
! FUNCTION VALUE:
!    LOGICAL :: stat
!      If .FALSE. element is degenerate or not a Whitney element
!   
!******************************************************************************
!------------------------------------------------------------------------------

     Type(Element_t) :: Element
     REAL(KIND=dp) :: Basis(:),dBasisdx(:,:),WhitneyBasis(:,:),dWhitneyBasisdx(:,:,:)
     INTEGER :: nfaces
     LOGICAL :: stat
!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------

     INTEGER :: i,j,k,l,q,n,dim,cdim,ip,jp,kp
     INTEGER, DIMENSION(:), POINTER :: Ind
     REAL(KIND=dp), DIMENSION(3,3) :: apu
     REAL (KIND=dp) :: Edge(3,3)
!------------------------------------------------------------------------------

     n    = Element % Type % NumberOfNodes
     dim  = Element % Type % DIMENSION
     cdim = CoordinateSystemDimension()

     IF ( (dim /= 3) .OR. (cdim /= 3 ) ) THEN
       stat = .FALSE.
       CALL Error( 'Whitney2ElementInfo', &
              'Whitney elements implemented only in 3D' )
       RETURN
     END IF

     nfaces = 4 ! tetras, 6 for bricks not supported

     DO q=1,nfaces
! Find appropriate end nodes (i,j,k) for face q
       IF (nfaces == 4) THEN
! For tetras
         SELECT CASE (q)
           CASE(1)
           i=1
           j=2
           k=3
           CASE(2)
           i=1
           j=2
           k=4
           CASE(3)
           i=1
           j=3
           k=4
           CASE(4)
           i=2
           j=3
           k=4
         END SELECT
       ELSE
         CALL Fatal( 'Whitney2ElementInfo', &
              'Not appropriate number of edges for W2 elements' )
         STOP
       END IF

! Guess the face direction is defined between elements (not internal)
     Ind => Element % Nodeindexes
     IF ( (Ind(i) < Ind(j)) .and. (Ind(i) < Ind(k)) ) THEN
       ip = i
       IF  ( Ind(j) < Ind(k) ) THEN
         jp = j
         kp = k
       ELSE
         jp = k
         kp = j
       END IF
     ELSE IF ( ( Ind(j) < Ind(i) ) .and. ( Ind(j) < Ind(k) ) ) THEN
       ip = j
       IF ( Ind(i) < Ind(k) ) THEN
         jp = i
         kp = k
       ELSE
         jp = k
         kp = i
       END IF
     ELSE
       ip = k
       IF  ( Ind(i) < Ind(j) ) THEN
         jp = i
         kp = j
       ELSE
         jp = j
         kp = i
       END IF
     END IF

! Put the beef in here
! Components of the basis function q
       apu(1,1) = dBasisdx(jp,2)*dBasisdx(kp,3) - dBasisdx(jp,3)*dBasisdx(kp,2)
       apu(1,2) = dBasisdx(kp,2)*dBasisdx(ip,3) - dBasisdx(kp,3)*dBasisdx(ip,2)
       apu(1,3) = dBasisdx(ip,2)*dBasisdx(jp,3) - dBasisdx(ip,3)*dBasisdx(jp,2)
       apu(2,1) = dBasisdx(jp,3)*dBasisdx(kp,1) - dBasisdx(jp,1)*dBasisdx(kp,3)
       apu(2,2) = dBasisdx(kp,3)*dBasisdx(ip,1) - dBasisdx(kp,1)*dBasisdx(ip,3)
       apu(2,3) = dBasisdx(ip,3)*dBasisdx(jp,1) - dBasisdx(ip,1)*dBasisdx(jp,3)
       apu(3,1) = dBasisdx(jp,1)*dBasisdx(kp,2) - dBasisdx(jp,2)*dBasisdx(kp,1)
       apu(3,2) = dBasisdx(kp,1)*dBasisdx(ip,2) - dBasisdx(kp,2)*dBasisdx(ip,1)
       apu(3,3) = dBasisdx(ip,1)*dBasisdx(jp,2) - dBasisdx(ip,2)*dBasisdx(jp,1)
! Component k
       DO k=1,dim
         WhitneyBasis(q,k) = 2._dp * ( Basis(ip) * apu(k,1) + &
             Basis(jp) * apu(k,2) + Basis(kp) * apu(k,3) )
!         WhitneyBasis(q,k) = WhitneyBasis(q,k) / SQRT(SUM(CrossProduct(Edge(1,:),Edge(2,:))**2)) * 2._dp
! And its derivative l
         DO l=1,dim
           dWhitneyBasisdx(q,k,l) = 2._dp * ( dBasisdx(ip,l) * apu(k,1) + &
               dBasisdx(jp,l) * apu(k,2) + dBasisdx(kp,l) * apu(k,3) )
         END DO
       END DO
     END DO
   END FUNCTION Whitney2ElementInfo
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   FUNCTION ElementMetric(Elm,Nodes,Metric,DetG,dLBasisdx,LtoGMap) RESULT(Success)
DLLEXPORT ElementMetric
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!   
!    Compute contravariant metric tensor (=J^TJ)^-1 of element coordinate
!    system, and square root of determinant of covariant metric tensor
!    (=sqrt(det(J^TJ)))
!
!  ARGUMENTS:
!   Type(Element_t) :: element
!     INPUT: element structure
!     
!   Type(Nodes_t) :: Nodes
!     INPUT: element nodal coordinates
!
!   REAL(KIND=dp) :: Metric(:,:)
!     OUTPUT: Contravariant metric tensor
!
!   REAL(KIND=dp) :: DetG
!     OUTPUT: SQRT of determinant of element coordinate metric
!
!   REAL(KIND=dp) :: dLBasisdx(:)
!     INPUT: Derivatives of element basis function with respect to local
!            coordinates
!
!  FUNCTION VALUE:
!     LOGICAL :: stat
!       If .FALSE. element is degenerate.
!    
!******************************************************************************
!------------------------------------------------------------------------------

      Type(Element_t)  :: Elm
      Type(Nodes_t)    :: Nodes
      REAL(KIND=dp) :: Metric(:,:),dLBasisdx(:,:),DetG, LtoGMap(3,3)
!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
     LOGICAL :: Success

     REAL(KIND=dp) :: dx(3,3),G(3,3),GI(3,3),s
     REAL(KIND=dp), DIMENSION(:), POINTER :: x,y,z

     INTEGER :: cdim,dim,i,j,k,n
!------------------------------------------------------------------------------
     success = .TRUE.

     x => nodes % x
     y => nodes % y
     z => nodes % z

     cdim = CoordinateSystemDimension()
     dim  = elm % Type % Dimension
     n    = elm % Type % NumberOfNodes

!------------------------------------------------------------------------------
!    Partial derivatives of global coordinates with respect to local coordinates
!------------------------------------------------------------------------------
     DO i=1,dim
        dx(1,i) = SUM( x(1:n)*dLBasisdx(1:n,i) )
        dx(2,i) = SUM( y(1:n)*dLBasisdx(1:n,i) )
        dx(3,i) = SUM( z(1:n)*dLBasisdx(1:n,i) )
     END DO
!------------------------------------------------------------------------------
!    Compute the covariant metric tensor of the element coordinate system
!------------------------------------------------------------------------------
     G = 0.0d0
     DO i=1,dim
        DO j=1,dim
           s = 0.0d0
           DO k=1,cdim
             s = s + dx(k,i)*dx(k,j)
           END DO
           G(i,j) = s
        END DO
     END DO
!------------------------------------------------------------------------------
!    Convert the metric to contravariant base, and compute the SQRT(DetG)
!------------------------------------------------------------------------------
     SELECT CASE( dim )
!------------------------------------------------------------------------------
!      Line elements
!------------------------------------------------------------------------------
       CASE (1)
         DetG  = G(1,1)

         IF ( DetG <= 0.0d0 ) THEN
           WRITE( Message, * ) 'Degenerate 1D element: ', DetG
           CALL Error( 'ElementMetric', Message )
           success = .FALSE.
           RETURN
         END IF

         Metric(1,1) = 1.0d0 / DetG
         DetG  = SQRT( DetG )

!------------------------------------------------------------------------------
!      Surface elements
!------------------------------------------------------------------------------
       CASE (2)
         DetG = ( G(1,1)*G(2,2) - G(1,2)*G(2,1) )

         IF ( DetG <= 0.0d0 ) THEN
           WRITE( Message, * ) 'Degenerate 2D element: ', DetG
           CALL Error( 'ElementMetric', Message )
           IF ( cdim < dim ) THEN
              WRITE( Message, * ) '2d element in 1d coordinate system?'
              CALL Error( 'ElementMetric', Message )
           END IF
           success = .FALSE.
           RETURN
         END IF

         Metric(1,1) =  G(2,2) / DetG
         Metric(1,2) = -G(1,2) / DetG
         Metric(2,1) = -G(2,1) / DetG
         Metric(2,2) =  G(1,1) / DetG
         DetG = SQRT(DetG)

!------------------------------------------------------------------------------
!      Volume elements
!------------------------------------------------------------------------------
       CASE (3)
         DetG = G(1,1) * ( G(2,2)*G(3,3) - G(2,3)*G(3,2) ) + &
                G(1,2) * ( G(2,3)*G(3,1) - G(2,1)*G(3,3) ) + &
                G(1,3) * ( G(2,1)*G(3,2) - G(2,2)*G(3,1) )

         IF ( DetG <= 0.0d0 ) THEN
           WRITE( Message, * ) 'Degenerate 3D element: ', DetG
           CALL Error( 'ElementMetric', Message )
           IF ( cdim < dim ) THEN
            WRITE( Message, * ) &
                   '2d/3d element in 1d/2d coordinate system?'
            CALL Error( 'ElementMetric', Message )
           END IF
           success = .FALSE.
           RETURN
         END IF

         CALL InvertMatrix3x3( G,GI,detG )
         Metric = GI
         DetG = SQRT(DetG)
     END SELECT

     LtoGMap(1:cdim,1:dim) = MATMUL(dx(1:cdim,1:dim),Metric(1:dim,1:dim))
!------------------------------------------------------------------------------
   END FUNCTION ElementMetric
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   SUBROUTINE GlobalFirstDerivativesInternal( elm,nodes,df,gx,gy,gz, &
                       Metric,dLBasisdx )
DLLEXPORT GlobalFirstDerivativesInternal
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Given element structure return value of the first partial derivatives with
!    respect to global coordinates of a quantity x given at element nodes at
!    local coordinate point u,v,w inside the element. Element basis functions
!    are used to compute the value. This is internal version,and shoudnt
!    usually be called directly by the user, but trough the wrapper routine
!    GlobalFirstDerivatives.
!
!  ARGUMENTS:
!    Type(Element_t) :: element
!      INPUT: element structure
!
!    Type(Nodes_t) :: nodes
!      INPUT: element nodal coordinate arrays
!     
!     REAL(KIND=dp) :: f(:)
!      INPUT: Nodal values of the quantity whose partial derivative we want to know
!
!     REAL(KIND=dp) :: gx = @f(u,v)/@x, gy = @f(u,v)/@y, gz = @f(u,v)/@z
!      OUTPUT: Values of the partial derivatives
!
!     REAL(KIND=dp) :: Metric(:,:)
!      INPUT: Contravariant metric tensor of the element coordinate system
!
!     REAL(KIND=dp), OPTIONAL :: dLBasisdx(:,:)
!      INPUT: Values of partial derivatives with respect to local coordinates
!
!   FUNCTION VALUE:
!      .TRUE. if element is ok, .FALSE. if degenerated
!
!******************************************************************************
   !
   ! Return value of first derivatives of a quantity f in global
   ! coordinates at point (u,v) in gx,gy and gz.
   !
     Type(Element_t) :: elm
     Type(Nodes_t) :: nodes
 
     REAL(KIND=dp) :: df(:),Metric(:,:)
     REAL(KIND=dp) :: gx,gy,gz
     REAL(KIND=dp) :: dLBasisdx(:,:)

!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------

     REAL(KIND=dp), DIMENSION(:), POINTER :: x,y,z
     REAL(KIND=dp) :: dx(3,3),dfc(3),s

     INTEGER :: cdim,dim,i,j,n,NB
!------------------------------------------------------------------------------

     n    = elm % Type % NumberOfNodes
     dim  = elm % Type % Dimension
     cdim = CoordinateSystemDimension()

     x => nodes % x
     y => nodes % y
     z => nodes % z
!------------------------------------------------------------------------------
!    Partial derivatives of global coordinates with respect to local, and
!    partial derivatives of the quantity given, also with respect to local
!    coordinates
!------------------------------------------------------------------------------
     SELECT CASE(cdim)
       CASE(1)
         DO i=1,dim
            dx(1,i) = SUM( x(1:n)*dLBasisdx(1:n,i) )
         END DO

       CASE(2)
         DO i=1,dim
            dx(1,i) = SUM( x(1:n)*dLBasisdx(1:n,i) )
            dx(2,i) = SUM( y(1:n)*dLBasisdx(1:n,i) )
         END DO

       CASE(3)
         DO i=1,dim
            dx(1,i) = SUM( x(1:n)*dLBasisdx(1:n,i) )
            dx(2,i) = SUM( y(1:n)*dLBasisdx(1:n,i) )
            dx(3,i) = SUM( z(1:n)*dLBasisdx(1:n,i) )
         END DO
     END SELECT
!------------------------------------------------------------------------------
!    Contravariant components of partials in element coordinates
!------------------------------------------------------------------------------
     DO i=1,dim
       s = 0.0d0
       DO j=1,dim
         s = s + Metric(i,j) * df(j)
       END DO
       dfc(i) = s
     END DO
!------------------------------------------------------------------------------
!    Transform partials to space coordinates
!------------------------------------------------------------------------------
     gx = 0.0d0
     gy = 0.0d0
     gz = 0.0d0
     SELECT CASE(cdim)
       CASE(1)
         gx = SUM( dx(1,1:dim) * dfc(1:dim) )

       CASE(2)
         gx = SUM( dx(1,1:dim) * dfc(1:dim) )
         gy = SUM( dx(2,1:dim) * dfc(1:dim) )

       CASE(3)
         gx = SUM( dx(1,1:dim) * dfc(1:dim) )
         gy = SUM( dx(2,1:dim) * dfc(1:dim) )
         gz = SUM( dx(3,1:dim) * dfc(1:dim) )
     END SELECT

   END SUBROUTINE GlobalFirstDerivativesInternal
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   SUBROUTINE GlobalFirstDerivatives( Elm, Nodes, df, gx, gy, gz, &
                    Metric, dLBasisdx )
DLLEXPORT GlobalFirstDerivatives
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!   Given element structure return value of the first partial derivative with
!   respect to global coordinates of a quantity f given at element nodes at
!   local coordinate point u,v,w inside the element. Element basis functions
!   are used to compute the value.
!
!  ARGUMENTS:
!   Type(Element_t) :: element
!     INPUT: element structure
!
!   Type(Nodes_t) :: nodes
!     INPUT: element nodal coordinate arrays
!     
!   REAL(KIND=dp) :: f(:)
!     INPUT: Nodal values of the quantity whose partial derivatives we want
!            to know
!
!   REAL(KIND=dp) :: gx=@f(u,v,w)/@x, gy=@f(u,v,w)/@y, gz=@f(u,v,w)/@z
!     OUTPUT: Values of the partial derivatives
!
!   REAL(KIND=dp) :: u,v,w
!     INPUT: Point at which to evaluate the partial derivative
!
!   REAL(KIND=dp)L :: dLBasisdx(:,:)
!     INPUT: Values of partial derivatives of basis functions with respect to
!            local coordinates
!
!   REAL(KIND=dp), OPTIONAL :: dBasisdx(:,:)
!     INPUT: Values of partial derivatives of basis functions with respect to
!            global coordinates can be given here, if known, otherwise they
!            will be computed from the element basis functions.
!
!******************************************************************************

     Type(Element_t) :: elm
     Type(Nodes_t) :: nodes

     REAL(KIND=dp) :: gx,gy,gz
     REAL(KIND=dp) :: dLBasisdx(:,:),Metric(:,:),df(:)

!    Local variables
!------------------------------------------------------------------------------
     INTEGER :: n
!------------------------------------------------------------------------------

    CALL GlobalFirstDerivativesInternal( Elm, Nodes, df, &
              gx, gy, gz, Metric, dLBasisdx )

   END SUBROUTINE GlobalFirstDerivatives
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   FUNCTION InterpolateInElement( elm,f,u,v,w,Basis ) RESULT(value)
DLLEXPORT InterpolateInElement
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!   Given element structure return value of a quantity x given at element nodes
!   at local coordinate point u inside the element. Element basis functions are
!   used to compute the value. This is just a wrapper routine and will call the
!   real function according to element dimension.   
!
!  ARGUMENTS:
!   Type(Element_t) :: element
!     INPUT: element structure
!     
!    REAL(KIND=dp) :: f(:)
!     INPUT: Nodal values of the quantity whose value we want to know
!
!    REAL(KIND=dp) :: u,v,w
!     INPUT: Point at which to evaluate the value
!
!    REAL(KIND=dp), OPTIONAL :: Basis(:)
!      INPUT: Values of the basis functions at the point u,v,w can be given here,
!      if known, otherwise the will be computed from the definition
!                 
!  FUNCTION VALUE:
!     REAL(KIND=dp) :: y
!       value of the quantity y = x(u,v,w)
!    
!******************************************************************************

     Type(Element_t) :: elm
     REAL(KIND=dp) :: u,v,w
     REAL(KIND=dp) :: f(:)
     REAL(KIND=dp), OPTIONAL :: Basis(:)

!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
     REAL(KIND=dp) :: value
     INTEGER :: n

     IF ( PRESENT( Basis ) ) THEN
!------------------------------------------------------------------------------
!      Basis function values given, just sum the result ...
!------------------------------------------------------------------------------
       n = elm % Type % NumberOfNodes
       value = SUM( f(1:n)*Basis(1:n) )
     ELSE
!------------------------------------------------------------------------------
!      ... otherwise compute from the definition.
!------------------------------------------------------------------------------
       SELECT CASE (elm % Type % Dimension)
         CASE (1)
           value = InterpolateInElement1D( elm,f,u )
         CASE (2)
           value = InterpolateInElement2D( elm,f,u,v )
         CASE (3)
           value = InterpolateInElement3D( elm,f,u,v,w )
       END SELECT
     END IF
  
   END FUNCTION InterpolateInElement
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   SUBROUTINE GlobalSecondDerivatives(elm,nodes,f,values,u,v,w,Metric,dBasisdx)
DLLEXPORT GlobalSecondDerivatives
!------------------------------------------------------------------------------
!******************************************************************************
!  
!       DESCRIPTION:
!          Compute elementwise matrix of second partial derivatives
!          at given point u,v,w in global coordinates.
!  
!       Parameters:
!  
!           Input:   (Element_t) structure describing the element
!                    (Nodes_t)   element nodal coordinates
!                    (double precision) F nodal values of the quantity
!                    (double precision) u,v point at which to evaluate
!  
!           Output:   3x3 matrix (values) of partial derivatives
!  
!*****************************************************************************

     Type(Nodes_t)   :: nodes
     Type(Element_t) :: elm
 
     REAL(KIND=dp) :: u,v,w
     REAL(KIND=dp) ::  f(:),Metric(:,:)
     REAL(KIND=dp) ::  values(:,:)
     REAL(KIND=dp), OPTIONAL :: dBasisdx(:,:)
!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
     INTEGER :: i,j,k,l,dim,cdim

     REAL(KIND=dp), DIMENSION(3,3,3) :: C1,C2,ddx
     REAL(KIND=dp), DIMENSION(3)     :: df
     REAL(KIND=dp), DIMENSION(3,3)   :: cddf,ddf,dx

     REAL(KIND=dp), DIMENSION(:), POINTER :: x,y,z
     REAL(KIND=dp) :: s

     INTEGER :: n
!------------------------------------------------------------------------------
#if 1
!
! This is actually not quite correct...
!
     IF ( elm % Type % BasisFunctionDegree <= 1 ) RETURN
#else
!
! this is ...
!
     IF ( elm % Type % ElementCode <= 202 .OR. &
          elm % Type % ElementCode == 303 .OR. &
          elm % Type % ElementCode == 504 ) RETURN
#endif

     n  = elm % Type % NumberOfNodes
     x => nodes % x
     y => nodes % y
     z => nodes % z

     dim  = elm % Type % DIMENSION
     cdim = CoordinateSystemDimension()

!------------------------------------------------------------------------------
!    Partial derivatives of the basis functions are given, just
!    sum for the first partial derivatives...
!------------------------------------------------------------------------------
     dx = 0.0d0
     SELECT CASE( cdim )
       CASE(1)
         DO i=1,dim
           dx(1,i) = SUM( x(1:n)*dBasisdx(1:n,i) )
           df(i)   = SUM( f(1:n)*dBasisdx(1:n,i) )
         END DO

       CASE(2)
         DO i=1,dim
           dx(1,i) = SUM( x(1:n)*dBasisdx(1:n,i) )
           dx(2,i) = SUM( y(1:n)*dBasisdx(1:n,i) )
           df(i)   = SUM( f(1:n)*dBasisdx(1:n,i) )
         END DO

       CASE(3)
         DO i=1,dim
           dx(1,i) = SUM( x(1:n)*dBasisdx(1:n,i) )
           dx(2,i) = SUM( y(1:n)*dBasisdx(1:n,i) )
           dx(3,i) = SUM( z(1:n)*dBasisdx(1:n,i) )
           df(i)   = SUM( f(1:n)*dBasisdx(1:n,i) )
         END DO
     END SELECT
!------------------------------------------------------------------------------
!     Get second partial derivatives with respect to local coordinates
!------------------------------------------------------------------------------
     SELECT CASE( dim )
       CASE(1)
!------------------------------------------------------------------------------
!        Line elements
!------------------------------------------------------------------------------
         ddx(1,1,1) = SecondDerivatives1D( elm,x,u )

       CASE(2)
!------------------------------------------------------------------------------
!        Surface elements
!------------------------------------------------------------------------------
         ddx(1,1:2,1:2) = SecondDerivatives2D( elm,x,u,v )
         ddx(2,1:2,1:2) = SecondDerivatives2D( elm,y,u,v )
         ddx(3,1:2,1:2) = SecondDerivatives2D( elm,z,u,v )

       CASE(3)
!------------------------------------------------------------------------------
!        Volume elements
!------------------------------------------------------------------------------
         ddx(1,1:3,1:3) = SecondDerivatives3D( elm,x,u,v,w )
         ddx(2,1:3,1:3) = SecondDerivatives3D( elm,y,u,v,w )
         ddx(3,1:3,1:3) = SecondDerivatives3D( elm,z,u,v,w )
      END SELECT
!
!------------------------------------------------------------------------------
!    Christoffel symbols of the second kind of the element coordinate system
!------------------------------------------------------------------------------
      DO i=1,dim
        DO j=1,dim
          DO k=1,dim
            s = 0.0d0
            DO l=1,cdim
              s = s + ddx(l,i,j)*dx(l,k)
            END DO
            C2(i,j,k) = s
          END DO
        END DO
      END DO
!------------------------------------------------------------------------------
!    Christoffel symbols of the first kind
!------------------------------------------------------------------------------
      DO i=1,dim
        DO j=1,dim
          DO k=1,dim
            s = 0.0d0
            DO l=1,dim
              s = s + Metric(k,l)*C2(i,j,l)
            END DO
            C1(i,j,k) = s
          END DO
        END DO
      END DO
!------------------------------------------------------------------------------
!     First add ordinary partials (change of the quantity with coordinates)...
!------------------------------------------------------------------------------
      SELECT CASE(dim)
        CASE(1)
          ddf(1,1) = SecondDerivatives1D( elm,f,u )

        CASE(2)
          ddf(1:2,1:2) = SecondDerivatives2D( elm,f,u,v )

        CASE(3)
          ddf(1:3,1:3) = SecondDerivatives3D( elm,f,u,v,w )
      END SELECT
!------------------------------------------------------------------------------
!     ... then add change of coordinates
!------------------------------------------------------------------------------
      DO i=1,dim
        DO j=1,dim
          s = 0.0d0
          DO k=1,dim
            s = s - C1(i,j,k)*df(k)
          END DO
          ddf(i,j) = ddf(i,j) + s
        END DO
      END DO
!------------------------------------------------------------------------------
!     Convert to contravariant base
!------------------------------------------------------------------------------
      DO i=1,dim
        DO j=1,dim
          s = 0.0d0
          DO k=1,dim
            DO l=1,dim
              s = s + Metric(i,k)*Metric(j,l)*ddf(k,l)
            END DO
          END DO
          cddf(i,j) = s
        END DO
      END DO
!------------------------------------------------------------------------------
!    And finally transform to global coordinates 
!------------------------------------------------------------------------------
      Values = 0.0d0
      DO i=1,cdim
        DO j=1,cdim
          s = 0.0d0
          DO k=1,dim
            DO l=1,dim
              s = s + dx(i,k)*dx(j,l)*cddf(k,l)    
            END DO
          END DO
          Values(i,j) = s
        END DO
      END DO
!------------------------------------------------------------------------------
   END SUBROUTINE GlobalSecondDerivatives
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   FUNCTION ElementDiameter( elm, nodes ) RESULT(hK)
DLLEXPORT ElementDiameter
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Figure out element diameter parameter for stablization.
!
!  ARGUMENTS:
!   Type(Element_t) :: element
!     INPUT: element structure
!     
!    Type(Nodes_t) :: nodes
!     INPUT: Nodal coordinate arrays of the element
!
!  FUNCTION VALUE:
!     REAL(KIND=dp) :: hK
!    
!******************************************************************************
     Type(Element_t) :: elm
     Type(Nodes_t) :: nodes

!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
     REAL(KIND=dp), DIMENSION(:), POINTER :: X,Y,Z

     REAL(KIND=dp) :: x0,y0,z0,hK,A,S,CX,CY,CZ
     REAL(KIND=dp) :: J11,J12,J13,J21,J22,J23,G11,G12,G21,G22
!------------------------------------------------------------------------------

     X => Nodes % x
     Y => Nodes % y
     Z => Nodes % z

     SELECT CASE( elm % Type % ElementCode / 100 )

       CASE(1)
         hK = 0.0d0

       CASE(2)
         hK = (X(2)-X(1))**2 + (Y(2)-Y(1))**2 + (Z(2)-Z(1))**2

!------------------------------------------------------------------------------
!       Triangular element
!------------------------------------------------------------------------------
       CASE(3) 
         J11 = X(2) - X(1)
         J12 = Y(2) - Y(1)
         J13 = Z(2) - Z(1)
         J21 = X(3) - X(1)
         J22 = Y(3) - Y(1)
         J23 = Z(3) - Z(1)
         G11 = J11**2  + J12**2  + J13**2
         G12 = J11*J21 + J12*J22 + J13*J23
         G22 = J21**2  + J22**2  + J23**2
         A = SQRT(G11*G22 - G12**2) / 2.0d0

         CX = ( X(1) + X(2) + X(3) ) / 3.0d0
         CY = ( Y(1) + Y(2) + Y(3) ) / 3.0d0
         CZ = ( Z(1) + Z(2) + Z(3) ) / 3.0d0

         s =     (X(1)-CX)**2 + (Y(1)-CY)**2 + (Z(1)-CZ)**2
         s = s + (X(2)-CX)**2 + (Y(2)-CY)**2 + (Z(2)-CZ)**2
         s = s + (X(3)-CX)**2 + (Y(3)-CY)**2 + (Z(3)-CZ)**2

         hK = 16.0d0*A*A / ( 3.0d0 * s )

!------------------------------------------------------------------------------
!      Quadrilateral
!------------------------------------------------------------------------------
       CASE(4)
          CX = (X(2)-X(1))**2 + (Y(2)-Y(1))**2 + (Z(2)-Z(1))**2
          CY = (X(4)-X(1))**2 + (Y(4)-Y(1))**2 + (Z(4)-Z(1))**2
          hk = 2*CX*CY/(CX+CY)

!------------------------------------------------------------------------------
!      Tetrahedron
!------------------------------------------------------------------------------
       CASE(5)

         CX = X(2) - X(1)
         CY = Y(2) - Y(1)
         CZ = Z(2) - Z(1)
         hK = CX**2 + CY**2 + CZ**2

         CX = X(3) - X(1)
         CY = Y(3) - Y(1)
         CZ = Z(3) - Z(1)
         hK = MIN( hK, CX**2 + CY**2 + CZ**2 )

         CX = X(4) - X(1)
         CY = Y(4) - Y(1)
         CZ = Z(4) - Z(1)
         hK = MIN( hK, CX**2 + CY**2 + CZ**2 )
          
         CX = X(3) - X(2)
         CY = Y(3) - Y(2)
         CZ = Z(3) - Z(2)
         hK = MIN( hK, CX**2 + CY**2 + CZ**2 )

         CX = X(4) - X(2)
         CY = Y(4) - Y(2)
         CZ = Z(4) - Z(2)
         hK = MIN( hK, CX**2 + CY**2 + CZ**2 )

         CX = X(4) - X(3)
         CY = Y(4) - Y(3)
         CZ = Z(4) - Z(3)
         hK = MIN( hK, CX**2 + CY**2 + CZ**2 )

!------------------------------------------------------------------------------
!      Pyramid
!------------------------------------------------------------------------------
      CASE(6)
         CX = X(2) - X(1)
         CY = Y(2) - Y(1)
         CZ = Z(2) - Z(1)
         hK = CX**2 + CY**2 + CZ**2

         CX = X(3) - X(2)
         CY = Y(3) - Y(2)
         CZ = Z(3) - Z(2)
         hK = MIN( hK, CX**2 + CY**2 + CZ**2 )

         CX = X(4) - X(3)
         CY = Y(4) - Y(3)
         CZ = Z(4) - Z(3)
         hK = MIN( hK, CX**2 + CY**2 + CZ**2 )
          
         CX = X(4) - X(1)
         CY = Y(4) - Y(1)
         CZ = Z(4) - Z(1)
         hK = MIN( hK, CX**2 + CY**2 + CZ**2 )

         CX = X(5) - X(1)
         CY = Y(5) - Y(1)
         CZ = Z(5) - Z(1)
         hK = MIN( hK, CX**2 + CY**2 + CZ**2 )

         CX = X(5) - X(2)
         CY = Y(5) - Y(2)
         CZ = Z(5) - Z(2)
         hK = MIN( hK, CX**2 + CY**2 + CZ**2 )

         CX = X(5) - X(3)
         CY = Y(5) - Y(3)
         CZ = Z(5) - Z(3)
         hK = MIN( hK, CX**2 + CY**2 + CZ**2 )

         CX = X(5) - X(4)
         CY = Y(5) - Y(4)
         CZ = Z(5) - Z(4)
         hK = MIN( hK, CX**2 + CY**2 + CZ**2 )

          
!------------------------------------------------------------------------------
!      Wedge
!------------------------------------------------------------------------------
      CASE(7)
         CX = X(2) - X(1)
         CY = Y(2) - Y(1)
         CZ = Z(2) - Z(1)
         hK = CX**2 + CY**2 + CZ**2

         CX = X(3) - X(2)
         CY = Y(3) - Y(2)
         CZ = Z(3) - Z(2)
         hK = MIN( hK, CX**2 + CY**2 + CZ**2 )

         CX = X(3) - X(1)
         CY = Y(3) - Y(1)
         CZ = Z(3) - Z(1)
         hK = MIN( hK, CX**2 + CY**2 + CZ**2 )
          
         CX = X(5) - X(4)
         CY = Y(5) - Y(4)
         CZ = Z(5) - Z(4)
         hK = MIN( hK, CX**2 + CY**2 + CZ**2 )

         CX = X(6) - X(5)
         CY = Y(6) - Y(5)
         CZ = Z(6) - Z(5)
         hK = MIN( hK, CX**2 + CY**2 + CZ**2 )

         CX = X(6) - X(4)
         CY = Y(6) - Y(4)
         CZ = Z(6) - Z(4)
         hK = MIN( hK, CX**2 + CY**2 + CZ**2 )

         CX = X(1) - X(4)
         CY = Y(1) - Y(4)
         CZ = Z(1) - Z(4)
         hK = MIN( hK, CX**2 + CY**2 + CZ**2 )

         CX = X(2) - X(5)
         CY = Y(2) - Y(5)
         CZ = Z(2) - Z(5)
         hK = MIN( hK, CX**2 + CY**2 + CZ**2 )

         CX = X(3) - X(6)
         CY = Y(3) - Y(6)
         CZ = Z(3) - Z(6)
         hK = MIN( hK, CX**2 + CY**2 + CZ**2 )
          
!------------------------------------------------------------------------------
!      Brick
!------------------------------------------------------------------------------
       CASE(8)
         x0 = X(7) - X(1)
         y0 = Y(7) - Y(1)
         z0 = Z(7) - Z(1)
         hK = x0*x0 + y0*y0 + z0*z0

         x0 = X(8) - X(2)
         y0 = Y(8) - Y(2)
         z0 = Z(8) - Z(2)
         hK = MIN( hK,x0*x0 + y0*y0 + z0*z0  )

         x0 = X(5) - X(3)
         y0 = Y(5) - Y(3)
         z0 = Z(5) - Z(3)
         hK = MIN( hK,x0*x0 + y0*y0 + z0*z0 )

         x0 = X(6) - X(4)
         y0 = Y(6) - Y(4)
         z0 = Z(6) - Z(4)
         hK = MIN( hK,x0*x0 + y0*y0 + z0*z0 )
     END SELECT

     hK = SQRT( hK )
!------------------------------------------------------------------------------
  END FUNCTION ElementDiameter
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  FUNCTION TriangleInside( nx,ny,nz,x,y,z ) RESULT(inside)
DLLEXPORT TriangleInside
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!     Figure out if given point x,y,z is inside a trinagle, whose node
!     coordinates are given in nx,ny,nz. Method: Invert the basis
!     functions....
!
!  ARGUMENTS:
!    REAL(KIND=dp) :: nx(:),ny(:),nz(:)
!      INPUT:  Node coordinate arrays
!
!    REAL(KIND=dp) :: x,y,z
!      INPUT: point which to consider
!
!  FUNCTION VALUE:
!    LOGICAL :: inside
!       result of the in/out test
!    
!******************************************************************************
!------------------------------------------------------------------------------

    REAL(KIND=dp) :: nx(:),ny(:),nz(:),x,y,z

!------------------------------------------------------------------------------
!   Local variables
!------------------------------------------------------------------------------
    LOGICAL :: inside

    REAL(KIND=dp) :: a00,a01,a10,a11,b00,b01,b10,b11,detA,px,py,u,v
!------------------------------------------------------------------------------

    inside = .FALSE.

    IF ( MAXVAL(nx) < x .OR. MAXVAL(ny) < y ) RETURN
    IF ( MINVAL(nx) > x .OR. MINVAL(ny) > y ) RETURN

    A00 = nx(2) - nx(1)
    A01 = nx(3) - nx(1)
    A10 = ny(2) - ny(1)
    A11 = ny(3) - ny(1)

    detA = A00*A11 - A01*A10
    IF ( ABS(detA) < AEPS ) RETURN

    detA = 1 / detA

    B00 =  A11*detA
    B01 = -A01*detA
    B10 = -A10*detA
    B11 =  A00*detA

    px = x - nx(1)
    py = y - ny(1)
    u = 0.0d0
    v = 0.0d0

    u = B00*px + B01*py
    IF ( u < 0.0d0 .OR. u > 1.0d0 ) RETURN

    v = B10*px + B11*py
    IF ( v < 0.0d0 .OR. v > 1.0d0 ) RETURN

    inside = (u + v <=  1.0d0)
!------------------------------------------------------------------------------
   END FUNCTION TriangleInside
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   FUNCTION QuadInside( nx,ny,nz,x,y,z ) RESULT(inside)
DLLEXPORT QuadInside
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!     Figure out if given point x,y,z is inside a quadrilateral, whose
!     node coordinates are given in nx,ny,nz. Method: Invert the
!     basis functions....
!
!  ARGUMENTS:
!    REAL(KIND=dp) :: nx(:),ny(:),nz(:)
!      INPUT:  Node coordinate arrays
!
!    REAL(KIND=dp) :: x,y,z
!      INPUT: point which to consider
!
!  FUNCTION VALUE:
!    LOGICAL :: inside
!       result of the in/out test
!    
!******************************************************************************
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: nx(:),ny(:),nz(:),x,y,z
!------------------------------------------------------------------------------
!   Local variables
!------------------------------------------------------------------------------
    LOGICAL :: inside

    REAL(KIND=dp) :: r,a,b,c,d,ax,bx,cx,dx,ay,by,cy,dy,px,py,u,v
!------------------------------------------------------------------------------
    inside = .FALSE.

    IF ( MAXVAL(nx) < x .OR. MAXVAL(ny) < y ) RETURN
    IF ( MINVAL(nx) > x .OR. MINVAL(ny) > y ) RETURN

    ax = 0.25*(  nx(1) + nx(2) + nx(3) + nx(4) )
    bx = 0.25*( -nx(1) + nx(2) + nx(3) - nx(4) )
    cx = 0.25*( -nx(1) - nx(2) + nx(3) + nx(4) )
    dx = 0.25*(  nx(1) - nx(2) + nx(3) - nx(4) )

    ay = 0.25*(  ny(1) + ny(2) + ny(3) + ny(4) )
    by = 0.25*( -ny(1) + ny(2) + ny(3) - ny(4) )
    cy = 0.25*( -ny(1) - ny(2) + ny(3) + ny(4) )
    dy = 0.25*(  ny(1) - ny(2) + ny(3) - ny(4) )

    px = x - ax
    py = y - ay

    a = cy*dx - cx*dy
    b = bx*cy - by*cx + dy*px - dx*py
    c = by*px - bx*py

    u = 0.0d0
    v = 0.0d0

    IF ( ABS(a) < AEPS ) THEN
      r = -c / b
      IF ( r < -1.0d0 .OR. r > 1.0d0 ) RETURN

      v = r
      u = (px - cx*r)/(bx + dx*r)
      inside = (u >= -1.0d0 .AND. u <= 1.0d0)
      RETURN
    END IF

    d = b*b - 4*a*c
    IF ( d < 0.0d0 ) RETURN

    r = 1.0d0/(2.0d0*a)
    b = r*b
    d = r*SQRT(d)

    r = -b + d
    IF ( r >= -1.0d0 .AND. r <= 1.0d0 ) THEN
      v = r
      u = (px - cx*r)/(bx + dx*r)
        
      IF ( u >= -1.0d0 .AND. u <= 1.0d0 ) THEN
        inside = .TRUE.
        RETURN
      END IF
    END IF

    r = -b - d
    IF ( r >= -1.0d0 .AND. r <= 1.0d0 ) THEN
      v = r
      u = (px - cx*r)/(bx + dx*r)
      inside = u >= -1.0d0 .AND. u <= 1.0d0
      RETURN
    END IF
!------------------------------------------------------------------------------
  END FUNCTION QuadInside
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  FUNCTION TetraInside( nx,ny,nz,x,y,z ) RESULT(inside)
DLLEXPORT TetraInside
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!     Figure out if given point x,y,z is inside a tetrahedron, whose
!     node coordinates are given in nx,ny,nz. Method: Invert the
!     basis functions....
!
!  ARGUMENTS:
!    REAL(KIND=dp) :: nx(:),ny(:),nz(:)
!      INPUT:  Node coordinate arrays
!
!    REAL(KIND=dp) :: x,y,z
!      INPUT: point which to consider
!
!  FUNCTION VALUE:
!    LOGICAL :: inside
!       result of the in/out test
!    
!******************************************************************************
!------------------------------------------------------------------------------

    REAL(KIND=dp) :: nx(:),ny(:),nz(:),x,y,z

!------------------------------------------------------------------------------
!   Local variables
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: A00,A01,A02,A10,A11,A12,A20,A21,A22,detA
    REAL(KIND=dp) :: B00,B01,B02,B10,B11,B12,B20,B21,B22

    LOGICAL :: inside

    REAL(KIND=dp) :: px,py,pz,u,v,w
!------------------------------------------------------------------------------
    inside = .FALSE.

    IF ( MAXVAL(nx) < x .OR. MAXVAL(ny) < y .OR. MAXVAL(nz) < z ) RETURN
    IF ( MINVAL(nx) > x .OR. MINVAL(ny) > y .OR. MINVAL(nz) > z ) RETURN

    A00 = nx(2) - nx(1)
    A01 = nx(3) - nx(1)
    A02 = nx(4) - nx(1)

    A10 = ny(2) - ny(1)
    A11 = ny(3) - ny(1)
    A12 = ny(4) - ny(1)

    A20 = nz(2) - nz(1)
    A21 = nz(3) - nz(1)
    A22 = nz(4) - nz(1)

    detA =        A00*(A11*A22 - A12*A21)
    detA = detA + A01*(A12*A20 - A10*A22)
    detA = detA + A02*(A10*A21 - A11*A20)
    IF ( ABS(detA) < AEPS ) RETURN

    detA = 1 / detA

    px = x - nx(1)
    py = y - ny(1)
    pz = z - nz(1)

    B00 = (A11*A22 - A12*A21)*detA
    B01 = (A21*A02 - A01*A22)*detA
    B02 = (A01*A12 - A11*A02)*detA

    u = B00*px + B01*py + B02*pz
    IF ( u < 0.0d0 .OR. u > 1.0d0 ) RETURN


    B10 = (A12*A20 - A10*A22)*detA
    B11 = (A00*A22 - A20*A02)*detA
    B12 = (A10*A02 - A00*A12)*detA

    v = B10*px + B11*py + B12*pz
    IF ( v < 0.0d0 .OR. v > 1.0d0 ) RETURN


    B20 = (A10*A21 - A11*A20)*detA
    B21 = (A01*A20 - A00*A21)*detA
    B22 = (A00*A11 - A10*A01)*detA

    w = B20*px + B21*py + B22*pz
    IF ( w < 0.0d0 .OR. w > 1.0d0 ) RETURN

    inside = (u + v + w) <= 1.0d0
!------------------------------------------------------------------------------
  END FUNCTION TetraInside
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  FUNCTION BrickInside( nx,ny,nz,x,y,z ) RESULT(inside)
DLLEXPORT BrickInside
!******************************************************************************
!
!  DESCRIPTION:
!     Figure out if given point x,y,z is inside a brick, whose node coordinates
!     are given in nx,ny,nz. Method: Divide to tetrahedrons.
!
!  ARGUMENTS:
!    REAL(KIND=dp) :: nx(:),ny(:),nz(:)
!      INPUT:  Node coordinate arrays
!
!    REAL(KIND=dp) :: x,y,z
!      INPUT: point which to consider
!
!  FUNCTION VALUE:
!    LOGICAL :: inside
!       result of the in/out test
!    
!******************************************************************************
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: nx(:),ny(:),nz(:),x,y,z

!------------------------------------------------------------------------------
!   Local variables
!------------------------------------------------------------------------------
    LOGICAL :: inside

    INTEGER :: i,j
    REAL(KIND=dp) :: px(4),py(4),pz(4),r,s,t,maxx,minx,maxy,miny,maxz,minz

    INTEGER :: map(3,12)
!------------------------------------------------------------------------------
    map = RESHAPE( (/ 0,1,2,   0,2,3,   4,5,6,   4,6,7,   3,2,6,   3,6,7,  &
     1,5,6,   1,6,2,   0,4,7,   0,7,3,   0,1,5,   0,5,4 /), (/ 3,12 /) ) + 1
    
    inside = .FALSE.

    IF ( MAXVAL(nx) < x .OR. MAXVAL(ny) < y .OR. MAXVAL(nz) < z ) RETURN
    IF ( MINVAL(nx) > x .OR. MINVAL(ny) > y .OR. MINVAL(nz) > z ) RETURN

    px(1) = 0.125d0 * SUM(nx)
    py(1) = 0.125d0 * SUM(ny)
    pz(1) = 0.125d0 * SUM(nz)

    DO i=1,12
      px(2:4) = nx(map(1:3,i))
      py(2:4) = ny(map(1:3,i))
      pz(2:4) = nz(map(1:3,i))

      IF ( TetraInside( px,py,pz,x,y,z ) ) THEN
        inside = .TRUE.
        RETURN
      END IF
    END DO
!------------------------------------------------------------------------------
  END FUNCTION BrickInside
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
!   Normal will point  from more dense material to less dense
!   or outwards, if no elements on the other side
!------------------------------------------------------------------------------
  SUBROUTINE CheckNormalDirection( Boundary,Normal,x,y,z,turn )
DLLEXPORT CheckNormalDirection
!------------------------------------------------------------------------------

    Type(Element_t), POINTER :: Boundary
    Type(Nodes_t) :: Nodes
    REAL(KIND=dp) :: Normal(3),x,y,z
    LOGICAL, OPTIONAL :: turn
!------------------------------------------------------------------------------

    Type (Element_t), POINTER :: Element,LeftElement,RightElement

    INTEGER :: LMat,RMat,n,k

    REAL(KIND=dp) :: x1,y1,z1,LDens,RDens
    REAL(KIND=dp) :: nx(MAX_NODES),ny(MAX_NODES),nz(MAX_NODES)
!------------------------------------------------------------------------------

    k = Boundary % BoundaryInfo % OutBody

    LeftElement => Boundary % BoundaryInfo % Left
    IF ( ASSOCIATED(LeftELement) ) THEN
       RightElement => Boundary % BoundaryInfo % Right

       IF ( ASSOCIATED( RightElement ) ) THEN

         IF ( k > 0 ) THEN

            IF ( Boundary % BoundaryInfo % LBody == k ) THEN
               Element => RightElement
            ELSE
               Element => LeftElement
            END IF

         ELSE

            LMat = ListGetInteger( CurrentModel % Bodies( &
                   LeftElement % BodyId)  % Values, 'Material', &
                    minv=1, maxv=CurrentModel % NumberOfMaterials )

            RMat = ListGetInteger( CurrentModel % Bodies( &
                   RightElement % BodyId) % Values, 'Material', &
                    minv=1, maxv=CurrentModel % NumberOfMaterials )

            LDens = ListGetConstReal( CurrentModel % &
                           Materials(LMat) % Values, 'Density' )
  
            RDens = ListGetConstReal( CurrentModel % &
                           Materials(RMat) % Values, 'Density' )

            IF ( LDens > RDens ) THEN
              Element => LeftElement
            ELSE
              Element => RightElement
            END IF
         END IF
       ELSE
          Element => LeftElement
       END IF
    ELSE
       Element => Boundary % BoundaryInfo % Right
    END IF

    n = Element % Type % NumberOfNodes
    nx(1:n) = CurrentModel % Nodes % x(Element % NodeIndexes)
    ny(1:n) = CurrentModel % Nodes % y(Element % NodeIndexes)
    nz(1:n) = CurrentModel % Nodes % z(Element % NodeIndexes)

    SELECT CASE( Element % Type % ElementCode / 100 )
    CASE(2,4,8)
       x1 = InterpolateInElement( Element, nx, 0.0d0, 0.0d0, 0.0d0 )
       y1 = InterpolateInElement( Element, ny, 0.0d0, 0.0d0, 0.0d0 )
       z1 = InterpolateInElement( Element, nz, 0.0d0, 0.0d0, 0.0d0 )
    CASE(3)
       x1 = InterpolateInElement( Element, nx, 1.0d0/3, 1.0d0/3, 0.0d0 )
       y1 = InterpolateInElement( Element, ny, 1.0d0/3, 1.0d0/3, 0.0d0 )
       z1 = InterpolateInElement( Element, nz, 1.0d0/3, 1.0d0/3, 0.0d0 )
    CASE(5)
       x1 = InterpolateInElement( Element, nx, 1.0d0/4, 1.0d0/4, 1.0d0/4 )
       y1 = InterpolateInElement( Element, ny, 1.0d0/4, 1.0d0/4, 1.0d0/4 )
       z1 = InterpolateInElement( Element, nz, 1.0d0/4, 1.0d0/4, 1.0d0/4 )
    CASE(6)
       x1 = InterpolateInElement( Element, nx, 0.0d0, 0.0d0, 1.0d0/3 )
       y1 = InterpolateInElement( Element, ny, 0.0d0, 0.0d0, 1.0d0/3 )
       z1 = InterpolateInElement( Element, nz, 0.0d0, 0.0d0, 1.0d0/3 )
    CASE(7)
       x1 = InterpolateInElement( Element, nx, 1.0d0/3, 1.0d0/3, 0.0d0 )
       y1 = InterpolateInElement( Element, ny, 1.0d0/3, 1.0d0/3, 0.0d0 )
       z1 = InterpolateInElement( Element, nz, 1.0d0/3, 1.0d0/3, 0.0d0 )
    END SELECT
    x1 = x1 - x
    y1 = y1 - y
    z1 = z1 - z

    IF ( PRESENT(turn) ) turn = .FALSE.
    IF ( x1*Normal(1) + y1*Normal(2) + z1*Normal(3) > 0 ) THEN
       IF ( k /= Element % BodyId ) THEN
          Normal = -Normal
          IF ( PRESENT(turn) ) turn = .TRUE.
       END IF
    ELSE IF ( k == Element % BodyId ) THEN
       Normal = -Normal
       IF ( PRESENT(turn) ) turn = .TRUE.
    END IF
!------------------------------------------------------------------------------
  END SUBROUTINE CheckNormalDirection
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
!
!
!------------------------------------------------------------------------------
  FUNCTION NormalVector( Boundary,BoundaryNodes,u,v,Check ) RESULT(Normal)
DLLEXPORT NormalVector
!------------------------------------------------------------------------------
    Type(Element_t), POINTER :: Boundary
    Type(Nodes_t)   :: BoundaryNodes
    REAL(KIND=dp) :: u,v
    LOGICAL, OPTIONAL :: Check 
    REAL(KIND=dp) :: Normal(3)
!------------------------------------------------------------------------------
    LOGICAL :: DoCheck

    Type(ElementType_t),POINTER :: elt

    REAL(KIND=dp) :: Auu,Auv,Avu,Avv,detA,x,y,z
    REAL(KIND=dp) :: dxdu,dxdv,dydu,dydv,dzdu,dzdv

    REAL(KIND=dp), DIMENSION(:), POINTER :: nx,ny,nz

    REAL(KIND=dp) :: Metric(3,3),SqrtMetric,Symbols(3,3,3),dSymbols(3,3,3,3)
!------------------------------------------------------------------------------

    nx => BoundaryNodes % x
    ny => BoundaryNodes % y
    nz => BoundaryNodes % z

    IF ( Boundary % Type % DIMENSION == 1 ) THEN

      dxdu = FirstDerivative1D( Boundary,nx,u )
      dydu = FirstDerivative1D( Boundary,ny,u )
 
      detA = dxdu*dxdu + dydu*dydu
      detA = 1.0d0 / SQRT(detA)

      Normal(1) = -dydu * detA
      Normal(2) =  dxdu * detA
      Normal(3) =  0.0d0

    ELSE

      dxdu = FirstDerivativeInU2D( Boundary,nx,u,v )
      dydu = FirstDerivativeInU2D( Boundary,ny,u,v )
      dzdu = FirstDerivativeInU2D( Boundary,nz,u,v )

      dxdv = FirstDerivativeInV2D( Boundary,nx,u,v )
      dydv = FirstDerivativeInV2D( Boundary,ny,u,v )
      dzdv = FirstDerivativeInV2D( Boundary,nz,u,v )

      Auu = dxdu*dxdu + dydu*dydu + dzdu*dzdu
      Auv = dxdu*dxdv + dydu*dydv + dzdu*dzdv
      Avv = dxdv*dxdv + dydv*dydv + dzdv*dzdv

      detA = 1.0d0 / SQRT(Auu*Avv - Auv*Auv)

      Normal(1) = (dydu * dzdv - dydv * dzdu) * detA
      Normal(2) = (dxdv * dzdu - dxdu * dzdv) * detA
      Normal(3) = (dxdu * dydv - dxdv * dydu) * detA
    END IF

    DoCheck = .FALSE.
    IF ( PRESENT(Check) ) DoCheck = Check

    IF ( DoCheck ) THEN
      SELECT CASE( Boundary % Type % ElementCode / 100 ) 
      CASE(2,4)
        x = InterpolateInElement( Boundary,nx,0.0d0,0.0d0,0.0d0 )
        y = InterpolateInElement( Boundary,ny,0.0d0,0.0d0,0.0d0 )
        z = InterpolateInElement( Boundary,nz,0.0d0,0.0d0,0.0d0 )
      CASE(3)
        x = InterpolateInElement( Boundary,nx,1.0d0/3,1.0d0/3,0.0d0)
        y = InterpolateInElement( Boundary,ny,1.0d0/3,1.0d0/3,0.0d0)
        z = InterpolateInElement( Boundary,nz,1.0d0/3,1.0d0/3,0.0d0)
      END SELECT
      CALL CheckNormalDirection( Boundary,Normal,x,y,z )
    END IF
!------------------------------------------------------------------------------
  END FUNCTION NormalVector
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
! @todo Change to support p elements
  SUBROUTINE GlobalToLocal( u,v,w,x,y,z,Element,ElementNodes )
DLLEXPORT  GlobalToLocal
!------------------------------------------------------------------------------
!
! Convert global coordinates x,y,z inside element to local coordinates
! u,v,w of the element.
!
!------------------------------------------------------------------------------

    Type(Nodes_t) :: ElementNodes
    REAL(KIND=dp) :: x,y,z,u,v,w
    Type(Element_t), POINTER :: Element

!------------------------------------------------------------------------------

    INTEGER, PARAMETER :: MaxIter = 50

    INTEGER :: i,n

    REAL(KIND=dp) :: r,s,t,delta(3),J(3,3),J1(3,2),det,swap

!------------------------------------------------------------------------------

    u = 0.d0
    v = 0.d0
    w = 0.d0
    n = Element % Type % NumberOfNodes

    ! @todo Not supported yet
!   IF (ASSOCIATED(Element % PDefs)) THEN
!      CALL Fatal('GlobalToLocal','P elements not supported yet!')
!   END IF

!------------------------------------------------------------------------------
    DO i=1,Maxiter
!------------------------------------------------------------------------------
      r = InterpolateInElement( Element,ElementNodes % x(1:n),u,v,w ) - x
      s = InterpolateInElement( Element,ElementNodes % y(1:n),u,v,w ) - y
      t = InterpolateInElement( Element,ElementNodes % z(1:n),u,v,w ) - z

      IF ( r**2 + s**2 + t**2 < EPSILON(x) ) EXIT

      delta = 0.d0

      SELECT CASE( Element % Type % Dimension )
      CASE(1)

        J(1,1) = FirstDerivative1D( Element, ElementNodes % x, u )
        J(2,1) = FirstDerivative1D( Element, ElementNodes % y, u )
        J(3,1) = FirstDerivative1D( Element, ElementNodes % z, u )

        det = SUM( J(1:3,1)**2 )
        delta(1) = (r*J(1,1)+s*J(2,1)+t*J(3,1))/det

      CASE(2)

         J(1,1) = FirstDerivativeInU2D( Element, ElementNodes % x, u, v )
         J(1,2) = FirstDerivativeInV2D( Element, ElementNodes % x, u, v )
         J(2,1) = FirstDerivativeInU2D( Element, ElementNodes % y, u, v )
         J(2,2) = FirstDerivativeInV2D( Element, ElementNodes % y, u, v )


        SELECT CASE( CoordinateSystemDimension() )
           CASE(3)
              J(3,1) = FirstDerivativeInU2D( Element, ElementNodes % z, u, v )
              J(3,2) = FirstDerivativeInV2D( Element, ElementNodes % z, u, v )

              delta(1) = r
              delta(2) = s
              delta(3) = t
              delta = MATMUL( TRANSPOSE(J), delta )
              r = delta(1)
              s = delta(2)

              J(1:2,1:2) = MATMUL( TRANSPOSE(J(1:3,1:2)), J(1:3,1:2) )
              delta(3)   = 0.0d0
         END SELECT

         CALL SolveLinSys2x2( J(1:2,1:2), delta(1:2), (/ r, s/) )

      CASE(3)
        J(1,1) = FirstDerivativeInU3D( Element, ElementNodes % x, u, v, w )
        J(1,2) = FirstDerivativeInV3D( Element, ElementNodes % x, u, v, w )
        J(1,3) = FirstDerivativeInW3D( Element, ElementNodes % x, u, v, w )

        J(2,1) = FirstDerivativeInU3D( Element, ElementNodes % y, u, v, w )
        J(2,2) = FirstDerivativeInV3D( Element, ElementNodes % y, u, v, w )
        J(2,3) = FirstDerivativeInW3D( Element, ElementNodes % y, u, v, w )

        J(3,1) = FirstDerivativeInU3D( Element, ElementNodes % z, u, v, w )
        J(3,2) = FirstDerivativeInV3D( Element, ElementNodes % z, u, v, w )
        J(3,3) = FirstDerivativeInW3D( Element, ElementNodes % z, u, v, w )

        CALL SolveLinSys3x3( J, delta, (/ r, s, t /) )

      END SELECT

      u = u - delta(1)
      v = v - delta(2)
      w = w - delta(3)
!------------------------------------------------------------------------------
    END DO
!------------------------------------------------------------------------------

    IF ( i > MaxIter ) CALL Warn( 'GlobalToLocal', 'did not converge.' )
!------------------------------------------------------------------------------
  END SUBROUTINE GlobalToLocal
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE InvertMatrix3x3( G,GI,detG )
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: G(3,3),GI(3,3)
    REAL(KIND=dp) :: detG, s
!------------------------------------------------------------------------------
    s = 1.0 / DetG
    
    GI(1,1) =  s * (G(2,2)*G(3,3) - G(3,2)*G(2,3));
    GI(2,1) = -s * (G(2,1)*G(3,3) - G(3,1)*G(2,3));
    GI(3,1) =  s * (G(2,1)*G(3,2) - G(3,1)*G(2,2));
    
    GI(1,2) = -s * (G(1,2)*G(3,3) - G(3,2)*G(1,3));
    GI(2,2) =  s * (G(1,1)*G(3,3) - G(3,1)*G(1,3));
    GI(3,2) = -s * (G(1,1)*G(3,2) - G(3,1)*G(1,2));

    GI(1,3) =  s * (G(1,2)*G(2,3) - G(2,2)*G(1,3));
    GI(2,3) = -s * (G(1,1)*G(2,3) - G(2,1)*G(1,3));
    GI(3,3) =  s * (G(1,1)*G(2,2) - G(2,1)*G(1,2));
!------------------------------------------------------------------------------
  END SUBROUTINE InvertMatrix3x3
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  FUNCTION getTriangleFaceDirection( Element, FaceMap ) RESULT(globalDir)
!******************************************************************************
!
!  DESCRIPTION:
!     Given element and its face map (for some triangular face of element ), 
!     this routine returns global direction of triangle face so that 
!     functions are continuous over element boundaries
!
!  ARGUMENTS:
!    Type(Element_t) :: Element
!      INPUT: Element to get direction to
!
!    INTEGER :: FaceMap(3)
!      INPUT: Element triangular face map
!
!  FUNCTION VALUE:
!    INTEGER :: globalDir(3)
!       Global direction of triangular face as local node numbers.
!    
!******************************************************************************
!------------------------------------------------------------------------------
    IMPLICIT NONE

    Type(Element_t) :: Element
    INTEGER :: i, FaceMap(3), globalDir(3), nodes(3)

    nodes = 0
    
    ! Put global nodes of face into sorted order
    nodes(1:3) = Element % NodeIndexes( FaceMap )
    CALL sort(3, nodes)
    
    globalDir = 0
    ! Find local numbers of sorted nodes. These local nodes 
    ! span continuous functions over element boundaries
    DO i=1,Element % Type % NumberOfNodes
       IF (nodes(1) == Element % NodeIndexes(i)) THEN
          globalDir(1) = i
       ELSE IF (nodes(2) == Element % NodeIndexes(i)) THEN
          globalDir(2) = i
       ELSE IF (nodes(3) == Element % NodeIndexes(i)) THEN
          globalDir(3) = i
       END IF
    END DO
  END FUNCTION getTriangleFaceDirection


!------------------------------------------------------------------------------
  FUNCTION getSquareFaceDirection( Element, FaceMap ) RESULT(globalDir)
!******************************************************************************
!
!  DESCRIPTION:
!     Given element and its face map (for some square face of element ), 
!     this routine returns global direction of square face so that 
!     functions are continuous over element boundaries
!
!  ARGUMENTS:
!    Type(Element_t) :: Element
!      INPUT: Element to get direction to
!
!    INTEGER :: FaceMap(4)
!      INPUT: Element square face map
!
!  FUNCTION VALUE:
!    INTEGER :: globalDir(3)
!       Global direction of square face as local node numbers.
!    
!******************************************************************************
!------------------------------------------------------------------------------
    IMPLICIT NONE

    Type(Element_t) :: Element
    INTEGER :: i, A,B,C,D, FaceMap(4), globalDir(4), nodes(4), minGlobal

    ! Get global nodes 
    nodes(1:4) = Element % NodeIndexes( FaceMap )
    ! Find min global node
    minGlobal = nodes(1)
    A = 1
    DO i=2,4
       IF (nodes(i) < minGlobal) THEN
          A = i
          minGlobal = nodes(i)
       END IF
    END DO

    ! Now choose node B as the smallest node NEXT to min node
    B = MOD(A,4)+1
    C = MOD(A+3,4)
    IF (C == 0) C = 4
    D = MOD(A+2,4)
    IF (D == 0) D = 4
    IF (nodes(B) > nodes(C)) THEN
       i = B
       B = C
       C = i
    END IF

    ! Finally find local numbers of nodes A,B and C. They uniquely
    ! define a global face so that basis functions are continuous 
    ! over element boundaries
    globalDir = 0
    DO i=1,Element % Type % NumberOfNodes
       IF (nodes(A) == Element % NodeIndexes(i)) THEN
          globalDir(1) = i
       ELSE IF (nodes(B) == Element % NodeIndexes(i)) THEN
          globalDir(2) = i
       ELSE IF (nodes(C) == Element % NodeIndexes(i)) THEN
          globalDir(4) = i
       ELSE IF (nodes(D) == Element % NodeIndexes(i)) THEN
          globalDir(3) = i
       END IF
    END DO
  END FUNCTION getSquareFaceDirection


!------------------------------------------------------------------------------
  FUNCTION wedgeOrdering( ordering ) RESULT(retVal)
!******************************************************************************
!
!  DESCRIPTION:
!     Function checks if given local numbering of a square face
!     is legal for wedge element
!
!  ARGUMENTS:
!
!    INTEGER :: ordering(4)
!      INPUT: Local ordering of a wedge square face
!
!  FUNCTION VALUE:
!    INTEGER :: retVal
!       .TRUE. if given ordering is legal for wedge square face,
!       .FALSE. otherwise
!    
!******************************************************************************
!------------------------------------------------------------------------------
    IMPLICIT NONE
    
    INTEGER, DIMENSION(4), INTENT(IN) :: ordering
    LOGICAL :: retVal

    retVal = .FALSE.
    IF ((ordering(1) >= 1 .AND. ordering(1) <= 3 .AND.&
         ordering(2) >= 1 .AND. ordering(2) <= 3) .OR. &
       (ordering(1) >= 4 .AND. ordering(1) <= 6 .AND.&
       ordering(2) >= 4 .AND. ordering(2) <= 6)) THEN
       retVal = .TRUE.
    END IF
  END FUNCTION wedgeOrdering

END MODULE ElementDescription
