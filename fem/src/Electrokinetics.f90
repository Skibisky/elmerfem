!******************************************************************************
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
! *****************************************************************************
!  

! *
! ******************************************************************************
! *
! *                    Author:       Juha Ruokolainen
! *
! *                    Address: Center for Scientific Computing
! *                            Tietotie 6, P.O. BOX 405
! *                              02101 Espoo, Finland
! *                              Tel. +358 0 457 2723
! *                            Telefax: +358 0 457 2302
! *                          EMail: Juha.Ruokolainen@csc.fi
! *
! *                       Date: 08 Jun 1997
! *
! ******************************************************************************
! *                Module author: Thomas Zwinger
! *
! *                Modified by: Thomas Zwinger
! *
! *       Date of modification: 13 Apr 2005
! *
! *****************************************************************************
!******************************************************************************
! *        file for routines used for electro-kinetic flow simulation including
! *        heat transfer.
! *        file contains following functions:
! *
! *        helmholtz_smoluchowski1/2/3: Elmer Interface for component-whise
! *                                     computation of HS-velocity to function
! *                                     helmholtz_smoluchowski_comp
! *
! *        helmholtz_smoluchowski_comp:  calculates components of the velocity
! *                                     given by the electroosmotic slip
! *                                     condition at the boundary;
! *
! *        helmholtz_smoluchowski: calculates absolut tangential value of the
! *                                Helmholtz-Smoluchowski velocity for
! *                                electro-osmotic velocity slip condition
! *
! *        getJouleHeat: computes inductive heat source as a function of 
! *                       electric field. Needs conductivity as material 
! *                       parameter input
!----------------------------------------------------------------------------------
! ******************************************************************************
!  computes Helmholtz Smoluchowski velocity in x1 direction
! ******************************************************************************
FUNCTION helmholtz_smoluchowski1( Model, NodeNumber, dummyargument) RESULT(hs_velocity1)
!DEC$ATTRIBUTES DLLEXPORT :: helmholtz_smoluchowski1

  USE DefUtils
  IMPLICIT NONE
! external variables
! ------------------
  TYPE(Model_t) :: Model
  INTEGER :: NodeNumber
  REAL(KIND=dp) :: dummyargument, hs_velocity1


  INTERFACE 
     FUNCTION helmholtz_smoluchowski_comp( Model, NodeNumber, direction) RESULT(hs_velocity_comp)
       USE DefUtils
       IMPLICIT NONE
       ! external variables
       ! ------------------
       TYPE(Model_t) :: Model
       INTEGER :: NodeNumber, direction
       REAL(KIND=dp) :: hs_velocity_comp
     END FUNCTION helmholtz_smoluchowski_comp
  END INTERFACE

  ! ---------------------
  ! HS-velocity component
  ! ---------------------
  hs_velocity1 = helmholtz_smoluchowski_comp( Model, NodeNumber, 1)
END FUNCTION helmholtz_smoluchowski1
!----------------------------------------------------------------------------------
! ******************************************************************************
!  computes Helmholtz Smoluchowski velocity in x2 direction
! ******************************************************************************
FUNCTION helmholtz_smoluchowski2( Model, NodeNumber, dummyargument) RESULT(hs_velocity2)
!DEC$ATTRIBUTES DLLEXPORT ::helmholtz_smoluchowski2
  USE DefUtils
  IMPLICIT NONE
! external variables
! ------------------
  TYPE(Model_t) :: Model
  INTEGER :: NodeNumber
  REAL(KIND=dp) :: dummyargument, hs_velocity2


  INTERFACE 
     FUNCTION helmholtz_smoluchowski_comp( Model, NodeNumber, direction) RESULT(hs_velocity_comp)
       USE DefUtils
       IMPLICIT NONE
       ! external variables
       ! ------------------
       TYPE(Model_t) :: Model
       INTEGER :: NodeNumber, direction
       REAL(KIND=dp) :: hs_velocity_comp
     END FUNCTION helmholtz_smoluchowski_comp
  END INTERFACE

  ! ---------------------
  ! HS-velocity component
  ! ---------------------
  hs_velocity2 = helmholtz_smoluchowski_comp( Model, NodeNumber, 2)
END FUNCTION helmholtz_smoluchowski2


!----------------------------------------------------------------------------------
! ******************************************************************************
!  computes Helmholtz Smoluchowski velocity in x3 direction
! ******************************************************************************
FUNCTION helmholtz_smoluchowski3( Model, NodeNumber, dummyargument) RESULT(hs_velocity3)
!DEC$ATTRIBUTES DLLEXPORT :: helmholtz_smoluchowski3
  USE DefUtils
  IMPLICIT NONE
! external variables
! ------------------
  TYPE(Model_t) :: Model
  INTEGER :: NodeNumber
  REAL(KIND=dp) :: dummyargument, hs_velocity3


  INTERFACE 
     FUNCTION helmholtz_smoluchowski_comp( Model, NodeNumber, direction) RESULT(hs_velocity_comp)
       USE DefUtils
       IMPLICIT NONE
       ! external variables
       ! ------------------
       TYPE(Model_t) :: Model
       INTEGER :: NodeNumber, direction
       REAL(KIND=dp) :: hs_velocity_comp
     END FUNCTION helmholtz_smoluchowski_comp
  END INTERFACE

  ! ---------------------
  ! HS-velocity component
  ! ---------------------
  hs_velocity3 = helmholtz_smoluchowski_comp( Model, NodeNumber, 3)
END FUNCTION helmholtz_smoluchowski3

! ************************************************************************************
!  computes component of Helmholtz Smoluchowski velocity for given direction
! ************************************************************************************
!----------------------------------------------------------------------------------
FUNCTION helmholtz_smoluchowski_comp( Model, NodeNumber, direction) RESULT(hs_velocity_comp)
  USE DefUtils
  IMPLICIT NONE
! external variables
! ------------------
  TYPE(Model_t) :: Model
  INTEGER :: NodeNumber, direction
  REAL(KIND=dp) :: hs_velocity_comp
! internal variables
! ------------------
  INTEGER :: i, N, DIM, istat, body_id, material_id, eq_id, other_body_id,&
       bc_id, Nboundary, BoundaryElementNode, coordinateDirection, &
       dummyIntegerArray(1)
  INTEGER, TARGET :: NodeNumberTarget(1)
  INTEGER, DIMENSION(:), POINTER :: NodeNumberArray
  REAL(KIND=dp) :: dummyArray(1), viscosity, dielectricConstant, vacuumPerm, zetapotential,&
       electricField(3), tang_electricField(3), norm_electricField,&
       U, V, W, Normal(3), hs_velocity(3), eoMobility
  CHARACTER(LEN=MAX_NAME_LEN) :: ElectricFieldMethod
  LOGICAL :: GotIt, ElectricFieldExists, FirstTime=.TRUE., SkipThisTime=.FALSE.,& 
       CalcMobility
  TYPE(ValueList_t), POINTER :: ParentMaterial, BC
  TYPE(Element_t), POINTER :: BoundaryElement, ParentElement  
  TYPE(Nodes_t) :: Nodes
  TYPE(Variable_t), POINTER :: EField1, EField2,EField3 
! remember this
! -------------
  SAVE Nodes, DIM, FirstTime, vacuumPerm, SkipThisTime
! provide arrays to let the ListGetReal/Integer function 
! work with just a nodal value to be read in
! -------------------------------------------------------
  NodeNumberTarget(1) = NodeNumber
  NodeNumberArray => NodeNumberTarget
!---------------------End of Header section ------------------------------------
  !-----------------------------------------------------------------
  !    return zero in simulation setup
  !-----------------------------------------------------------------
  hs_velocity_comp = 0.0d00
  eoMobility = 0.0d00
  SkipThisTime = ListGetLogical(Model % Simulation, 'Initializaton Phase', GotIt)  
  IF (SkipThisTime) RETURN

  !-----------------------------------------------------------------
  ! things to be done for the first time only
  !-----------------------------------------------------------------
  IF (FirstTime) THEN
     DIM = CoordinateSystemDimension()
     N = Model % MaxElementNodes 
     ALLOCATE(Nodes % x(N), Nodes % y(N), Nodes % z(N),&
          STAT = istat)
     IF (istat /= 0) THEN
        CALL FATAL('electrokinetics (helmholtz_smoluchowski_comp)','Allocations failed')
     END IF
     vacuumPerm = ListGetConstReal( Model % Constants, 'Permittivity of Vacuum', GotIt )
     IF (.NOT. GotIt) THEN
        CALL WARN('electrokinetics (helmholtz_smoluchowski_comp)',&
             'No value for >Permittivity of Vacuum< found in section Constants')
        CALL WARN('electrokinetics (helmholtz_smoluchowski_comp)',&
             '         Using default SI value 8.8542E-12')
        vacuumPerm = 8.8542D-12
     END IF
     FirstTime = .FALSE.
  END IF
  !-------------------------------------------------------------------------
  ! get some information upon active boundary element and its parent element
  !-------------------------------------------------------------------------
  BoundaryElement => Model % CurrentElement
  IF ( .NOT. ASSOCIATED(BoundaryElement) ) THEN
     CALL FATAL('electrokinetics (helmholtz_smoluchowski_comp)','No boundary element found')
  END IF
  other_body_id = BoundaryElement % BoundaryInfo % outbody
  IF (other_body_id < 1) THEN ! only one body in calculation
     ParentElement => BoundaryElement % BoundaryInfo % Right
     IF ( .NOT. ASSOCIATED(ParentElement) ) ParentElement => BoundaryElement % BoundaryInfo % Left
  ELSE ! we are dealing with a body-body boundary and asume that the normal is pointing outwards
     ParentElement => BoundaryElement % BoundaryInfo % Right
     IF (ParentElement % BodyId == other_body_id) ParentElement => BoundaryElement % BoundaryInfo % Left
  END IF
  ! just to be on the save side, check again
  IF ( .NOT. ASSOCIATED(ParentElement) ) THEN
     CALL FATAL('electrokinetics (helmholtz_smoluchowski_comp)','No parent element found for boudnary element')
  END IF
  body_id = ParentElement % BodyId
  material_id = ListGetInteger(Model % Bodies(body_id) % Values, 'Material', GotIt)
  ParentMaterial => Model % Materials(material_id) % Values
  IF (.NOT. ASSOCIATED(ParentMaterial)) THEN
     CALL FATAL('electrokinetics (helmholtz_smoluchowski_comp)','No material values could be found')
  END IF
  eq_id = ListGetInteger( Model % Bodies(body_id) % Values,'Equation', &
       minv=1,maxv=Model % NumberOfEquations )
  bc_id = GetBCId(BoundaryElement)
  BC => GetBC(BoundaryElement)
  !-------------------------------------------
  ! Get normal of the boundary element at node
  !-------------------------------------------
  Nboundary = BoundaryElement % Type % NumberOfNodes
  DO BoundaryElementNode=1,Nboundary
     IF ( NodeNumber == BoundaryElement % NodeIndexes(BoundaryElementNode) ) EXIT
  END DO
  U = BoundaryElement % Type % NodeU(BoundaryElementNode)
  V = BoundaryElement % Type % NodeV(BoundaryElementNode)
  Nodes % x(1:Nboundary) = Model % Nodes % x(BoundaryElement % NodeIndexes)
  Nodes % y(1:Nboundary) = Model % Nodes % y(BoundaryElement % NodeIndexes)
  Nodes % z(1:Nboundary) = Model % Nodes % z(BoundaryElement % NodeIndexes)
  Normal = NormalVector( BoundaryElement, Nodes, U, V,.TRUE. )

  !-----------------------------------------------------------------
  ! get material parameters from boundary
  !-----------------------------------------------------------------  
  dummyArray = ListGetReal( BC, 'Zeta Potential', 1, NodeNumberArray, GotIt )
  CalcMobility = GotIt

  IF (.NOT.CalcMobility) THEN
     dummyArray = ListGetReal( BC, 'EO Mobility', 1, NodeNumberArray, GotIt )
     IF (.NOT.GotIt) THEN
        WRITE(Message,'(a,i3)' )'Neither zeta potential nor EO mobility found in boundary condition no.', bc_id
        CALL INFO('electrokinetics (helmholtz_smoluchowski)',Message,Level=4)
        CALL INFO('electrokinetics (helmholtz_smoluchowski)','setting EO mobility to 0', Level=4)
        eoMobility = 0.0d00
     ELSE
        eoMobility = dummyArray(1)
     END IF
  ELSE
     zetapotential = dummyArray(1)
  END IF

  
  !-----------------------------------------------------------------
  ! get material parameters from bulk (if needed)
  !-----------------------------------------------------------------
    IF (CalcMobility) THEN
     Model % CurrentElement => ParentElement ! we need this in case of the material parameter being a function
     dummyArray  = ListGetReal( ParentMaterial, 'Viscosity', 1, NodeNumberArray, GotIt)
     IF (.NOT. GotIt) THEN
        WRITE(Message,'(a,i3)' )'No viscosity found in material section no.', material_id
        CALL FATAL( 'electrokinetics (helmholtz_smoluchowski)',Message )
     ELSE
        viscosity = dummyArray(1)
     END IF
     dummyArray= ListGetReal( ParentMaterial, 'Relative Permittivity', 1, NodeNumberArray, GotIt )
     IF (.NOT. GotIt) THEN
        WRITE(Message,'(a,i3)' )&
             'No keyword >Relative Permittivity< found in material section no.', material_id
        CALL INFO('electrokinetics (helmholtz_smoluchowski)',Message,Level=4)
        CALL INFO('electrokinetics (helmholtz_smoluchowski)','setting to 1', Level=4)
        dielectricConstant = 1.0d00
     ELSE
        dielectricConstant = dummyArray(1)
     END IF
  END IF

  !-----------------------------------------------------------------
  ! get electric field
  !-----------------------------------------------------------------
  ElectricFieldMethod = ListGetString( Model % Equations(eq_id) % &
       Values, 'Electric Field', GotIt )
  IF ( .NOT.GotIt ) THEN 
     WRITE(Message,'(a,i3)' )'No external electric field defined for Equation no.', eq_id
     CALL Info('electrokinetics (helmholtz_smoluchowski)',Message, level=4)
     ElectricFieldExists = .FALSE.
     hs_velocity = 0.0D00
  ELSE
     ElectricFieldExists = .TRUE.
     IF ( ElectricFieldMethod == 'constant') THEN ! read field components from Material section
        ElectricFieldExists = .FALSE.
        dummyArray =  ListGetReal( ParentMaterial, 'Electric Field 1', 1, NodeNumberArray, GotIt )
        IF (.NOT. GotIt) THEN 
           electricField(1) = 0.0d00
        ELSE
           electricField(1) = dummyArray(1) 
           ElectricFieldExists = (ElectricFieldExists .OR. GotIt)
        END IF
        dummyArray =  ListGetReal( ParentMaterial, 'Electric Field 2', 1, NodeNumberArray, GotIt )
        IF (.NOT. GotIt) THEN 
           electricField(2) = 0.0d00
        ELSE
           electricField(2) = dummyArray(1)
           ElectricFieldExists = (ElectricFieldExists .OR. GotIt) 
        END IF
        dummyArray =  ListGetReal( ParentMaterial, 'Electric Field 3', 1, NodeNumberArray, GotIt )
        IF (.NOT. GotIt) THEN 
           electricField(3) = 0.0d00
        ELSE
           electricField(3) = dummyArray(1) 
           ElectricFieldExists = (ElectricFieldExists .OR. GotIt)
        END IF
        IF (.NOT. ElectricFieldExists) THEN
           WRITE(Message,'(a,i3)' )'No component for >Electric Field {1,2,3}< found in Material',&
                material_id, ' although defined as constant'
           CALL WARN('electrokinetics (helmholtz_smoluchowski)',Message)
        END IF
     ELSE IF ( ElectricFieldMethod == 'computed') THEN ! get Electric Field from Electrostatic Solver
        electricField = 0.0d00
        EField1 => VariableGet( Model % Variables, 'Electric Field 1' )
        IF (ASSOCIATED(EField1)) THEN
           electricField(1) = EField1%Values(EField1%Perm(NodeNumber))
           ElectricFieldExists = .TRUE.
!        ELSE
!           CALL INFO('electrokinetics (helmholtz_smoluchowski)',&
!                'No computed electric field 1 found', level=6)
        END IF
        IF (DIM .GE. 2) THEN
           EField2 => VariableGet( Model % Variables, 'Electric Field 2' )
           IF (ASSOCIATED(EField2)) THEN
              electricField(2) = EField2%Values(EField2%Perm(NodeNumber))
              ElectricFieldExists = .TRUE.
!           ELSE
!              CALL INFO('electrokinetics (helmholtz_smoluchowski)',&
!                   'No computed electric field 2 found', level=6)
           END IF
        END IF
        IF (DIM .GE. 3) THEN
           EField3 => VariableGet( Model % Variables, 'Electric Field 3' )
           IF (ASSOCIATED(EField3)) THEN
              electricField(3) = EField3%Values(EField3%Perm(NodeNumber))
              ElectricFieldExists = .TRUE.
!           ELSE
!              CALL INFO('electrokinetics (helmholtz_smoluchowski)',&
!                   'No computed electric field 3 found', Level=6)
           END IF
        END IF
     ELSE         
        WRITE(Message,'(a,a,a,i3)' ) 'Unknown entry, ', ElectricFieldMethod,&
             ',for keyword >Electric Field< for Equation no.', eq_id
        CALL WARN('electrokinetics (helmholtz_smoluchowski)',Message)
        ElectricFieldExists = .FALSE.
        hs_velocity = 0.0D00        
     END IF
  END IF
  Model % CurrentElement => BoundaryElement  ! restore correct pointer
  !---------------------------------------------
  ! compute the Helmholtz-Smoluchowski velocity
  !---------------------------------------------
  IF (ElectricFieldExists) THEN     
     norm_electricField = SUM(electricField(1:3)*Normal(1:3))
     tang_electricField(1:3)=0.0d00   
     DO i=1,DIM
        tang_electricField(i) = electricField(i) - norm_electricField*Normal(i)
     END DO  
     hs_velocity(1:3) = tang_electricField(1:3)*eoMobility
     hs_velocity_comp = hs_velocity(direction)
  END IF
END FUNCTION helmholtz_smoluchowski_comp

! **********************************************************************************************
!  computes absolute value of Helmholtz Smoluchowski velocity in tangential direction (2d, only)
! **********************************************************************************************
!----------------------------------------------------------------------------------
FUNCTION helmholtz_smoluchowski( Model, NodeNumber, dummyargument) RESULT(hs_velocity)
!DEC$ATTRIBUTES DLLEXPORT :: helmholtz_smoluchowski
  USE DefUtils
  IMPLICIT NONE
! external variables
! ------------------
  TYPE(Model_t) :: Model
  INTEGER :: NodeNumber
  REAL(KIND=dp) :: dummyargument, hs_velocity
! internal variables
! ------------------
  INTEGER :: i, N, DIM, istat, body_id, material_id, eq_id, other_body_id,&
       bc_id, Nboundary, BoundaryElementNode, coordinateDirection, &
       dummyIntegerArray(1)
  INTEGER, TARGET :: NodeNumberTarget(1)
  INTEGER, DIMENSION(:), POINTER :: NodeNumberArray
  REAL(KIND=dp) :: dummyArray(1), viscosity, dielectricConstant, vacuumPerm, zetapotential,&
       electricField(3), tang_electricField(3), norm_electricField,&
       U, V, W, Normal(3), Tangent(3), Tangent2(3), eoMobility
  CHARACTER(LEN=MAX_NAME_LEN) :: ElectricFieldMethod
  LOGICAL :: GotIt, ElectricFieldExists, FirstTime=.TRUE., SkipThisTime=.FALSE., &
       CalcMobility
  TYPE(ValueList_t), POINTER :: ParentMaterial, BC
  TYPE(Element_t), POINTER :: BoundaryElement, ParentElement  
  TYPE(Nodes_t) :: Nodes
  TYPE(Variable_t), POINTER :: EField1, EField2,EField3 
! remember this
! -------------
  SAVE Nodes, DIM, FirstTime, vacuumPerm, SkipThisTime
! provide arrays to let the ListGetReal/Integer function 
! work with just a nodal value to be read in
! -------------------------------------------------------
  NodeNumberTarget(1) = NodeNumber
  NodeNumberArray => NodeNumberTarget
!---------------------End of Header section ------------------------------------
  !-----------------------------------------------------------------
  !    return zero in simulation setup
  !-----------------------------------------------------------------
  hs_velocity = 0.0d00
  eoMobility = 0.0d00
  SkipThisTime = ListGetLogical(Model % Simulation, 'Initializaton Phase', GotIt)  
  IF (SkipThisTime) RETURN
  !-----------------------------------------------------------------
  ! things to be done for the first time only
  !-----------------------------------------------------------------
  IF (FirstTime) THEN
     DIM = CoordinateSystemDimension()
     N = Model % MaxElementNodes 
     ALLOCATE(Nodes % x(N), Nodes % y(N), Nodes % z(N),&
          STAT = istat)
     IF (istat /= 0) THEN
        CALL FATAL('electrokinetics (helmholtz_smoluchowski)','Allocations failed')
     END IF
     vacuumPerm = ListGetConstReal( Model % Constants, 'Permittivity of Vacuum', GotIt )
     IF (.NOT. GotIt) THEN
        CALL WARN('electrokinetics (helmholtz_smoluchowski)',&
             'No value for >Permittivity of Vacuum< found in section Constants')
        CALL WARN('electrokinetics (helmholtz_smoluchowski)',&
             '         Using default SI value 8.8542E-12')
        vacuumPerm = 8.8542D-12
     END IF
     FirstTime = .FALSE.
  END IF
  !-------------------------------------------------------------------------
  ! get some information upon active boundary element and its parent element
  !-------------------------------------------------------------------------
  BoundaryElement => Model % CurrentElement
  IF ( .NOT. ASSOCIATED(BoundaryElement) ) THEN
     CALL FATAL('electrokinetics (helmholtz_smoluchowski)','No boundary element found')
  END IF
  other_body_id = BoundaryElement % BoundaryInfo % outbody
  IF (other_body_id < 1) THEN ! only one body in calculation
     ParentElement => BoundaryElement % BoundaryInfo % Right
     IF ( .NOT. ASSOCIATED(ParentElement) ) ParentElement => BoundaryElement % BoundaryInfo % Left
  ELSE ! we are dealing with a body-body boundary and asume that the normal is pointing outwards
     ParentElement => BoundaryElement % BoundaryInfo % Right
     IF (ParentElement % BodyId == other_body_id) ParentElement => BoundaryElement % BoundaryInfo % Left
  END IF
  ! just to be on the save side, check again
  IF ( .NOT. ASSOCIATED(ParentElement) ) THEN
     CALL FATAL('electrokinetics (helmholtz_smoluchowski)','No parent element found for boudnary element')
  END IF
  body_id = ParentElement % BodyId
  material_id = ListGetInteger(Model % Bodies(body_id) % Values, 'Material', GotIt)
  ParentMaterial => Model % Materials(material_id) % Values
  IF (.NOT. ASSOCIATED(ParentMaterial)) THEN
     CALL FATAL('electrokinetics (helmholtz_smoluchowski)','No material values could be found')
  END IF
  eq_id = ListGetInteger( Model % Bodies(body_id) % Values,'Equation', &
       minv=1,maxv=Model % NumberOfEquations )
  bc_id = GetBCId(BoundaryElement)
  BC => GetBC(BoundaryElement)
  
  !-------------------------------------------
  ! Get normal of the boundary element at node
  !-------------------------------------------
  Nboundary = BoundaryElement % Type % NumberOfNodes
  DO BoundaryElementNode=1,Nboundary
     IF ( NodeNumber == BoundaryElement % NodeIndexes(BoundaryElementNode) ) EXIT
  END DO
  U = BoundaryElement % Type % NodeU(BoundaryElementNode)
  V = BoundaryElement % Type % NodeV(BoundaryElementNode)
  Nodes % x(1:Nboundary) = Model % Nodes % x(BoundaryElement % NodeIndexes)
  Nodes % y(1:Nboundary) = Model % Nodes % y(BoundaryElement % NodeIndexes)
  Nodes % z(1:Nboundary) = Model % Nodes % z(BoundaryElement % NodeIndexes)
  Normal = NormalVector( BoundaryElement, Nodes, U, V,.TRUE. )
  !-------------------------------------------------------
  ! Get tangential vector of the boundary element at node
  !-------------------------------------------------------
  IF (DIM .GE. 2) THEN
     CALL TangentDirections( Normal,Tangent,Tangent2)
  ELSE 
     CALL FATAL('electrokinetics (helmholtz_smoluchowski)',&
          'It does not make sense to implement a slip condition for one-dimensional flow (on points)')
  END IF  
  !-----------------------------------------------------------------
  ! get material parameters from boundary
  !-----------------------------------------------------------------
  
  dummyArray = ListGetReal( BC, 'Zeta Potential', 1, NodeNumberArray, GotIt )
  IF (.NOT. GotIt) THEN
     CalcMobility = .FALSE.
  ELSE
     zetapotential = dummyArray(1)
     CalcMobility = .TRUE.
  END IF

  IF (.NOT.CalcMobility) THEN
     dummyArray = ListGetReal( BC, 'EO Mobility', 1, NodeNumberArray, GotIt )
     IF (.NOT.GotIt) THEN
        WRITE(Message,'(a,i3)' )'Neither zeta potential nor EO mobility found in boundary condition no.', bc_id
        CALL INFO('electrokinetics (helmholtz_smoluchowski)',Message,Level=4)
        CALL INFO('electrokinetics (helmholtz_smoluchowski)','setting EO mobility to 0', Level=4)
        eoMobility = 0.0d00
     ELSE
        eoMobility = dummyArray(1)
     END IF
  END IF
  
  !-----------------------------------------------------------------
  ! get material parameters from bulk (if needed)
  !-----------------------------------------------------------------
  IF (CalcMobility) THEN
     Model % CurrentElement => ParentElement ! we need this in case of the material parameter being a function
     dummyArray  = ListGetReal( ParentMaterial, 'Viscosity', 1, NodeNumberArray, GotIt)
     IF (.NOT. GotIt) THEN
        WRITE(Message,'(a,i3)' )'No viscosity found in material section no.', material_id
        CALL FATAL( 'electrokinetics (helmholtz_smoluchowski)',Message )
     ELSE
        viscosity = dummyArray(1)
     END IF
     dummyArray= ListGetReal( ParentMaterial, 'Relative Permittivity', 1, NodeNumberArray, GotIt )
     IF (.NOT. GotIt) THEN
        WRITE(Message,'(a,i3)' )&
             'No kmeyword >Relative Permittivity< found in material section no.', material_id
        CALL INFO('electrokinetics (helmholtz_smoluchowski)',Message,Level=4)
        CALL INFO('electrokinetics (helmholtz_smoluchowski)','setting to 1', Level=4)
        dielectricConstant = 1.0d00
     ELSE
        dielectricConstant = dummyArray(1)
     END IF
  END IF

  !-----------------------------------------------------------------
  ! get electric field
  !-----------------------------------------------------------------
  ElectricFieldMethod = ListGetString( Model % Equations(eq_id) % &
       Values, 'Electric Field', GotIt )
  IF ( .NOT.GotIt ) THEN 
     WRITE(Message,'(a,i3)' )'No external electric field defined for Equation no.', eq_id
     CALL Info('electrokinetics (helmholtz_smoluchowski)',Message, level=4)
     ElectricFieldExists = .FALSE.
     hs_velocity = 0.0D00
  ELSE
     ElectricFieldExists = .TRUE.
     IF ( ElectricFieldMethod == 'constant') THEN ! read field components from Material section
        ElectricFieldExists = .FALSE.
        dummyArray =  ListGetReal( ParentMaterial, 'Electric Field 1', 1, NodeNumberArray, GotIt )
        IF (.NOT. GotIt) THEN 
           electricField(1) = 0.0d00
        ELSE
           electricField(1) = dummyArray(1) 
           ElectricFieldExists = (ElectricFieldExists .OR. GotIt)
        END IF
        dummyArray =  ListGetReal( ParentMaterial, 'Electric Field 2', 1, NodeNumberArray, GotIt )
        IF (.NOT. GotIt) THEN 
           electricField(2) = 0.0d00
        ELSE
           electricField(2) = dummyArray(1)
           ElectricFieldExists = (ElectricFieldExists .OR. GotIt) 
        END IF
        dummyArray =  ListGetReal( ParentMaterial, 'Electric Field 3', 1, NodeNumberArray, GotIt )
        IF (.NOT. GotIt) THEN 
           electricField(3) = 0.0d00
        ELSE
           electricField(3) = dummyArray(1) 
           ElectricFieldExists = (ElectricFieldExists .OR. GotIt)
        END IF
        IF (.NOT. ElectricFieldExists) THEN
           WRITE(Message,'(a,i3)' )'No component for >Electric Field {1,2,3}< found in Material',&
                material_id, ' although defined as constant'
           CALL WARN('electrokinetics (helmholtz_smoluchowski)',Message)
        END IF
     ELSE IF ( ElectricFieldMethod == 'computed') THEN ! get Electric Field from Electrostatic Solver
        electricField = 0.0d00
        EField1 => VariableGet( Model % Variables, 'Electric Field 1' )
        IF (ASSOCIATED(EField1)) THEN
           electricField(1) = EField1%Values(EField1%Perm(NodeNumber))
           ElectricFieldExists = .TRUE.
!        ELSE
!           CALL WARN('electrokinetics (helmholtz_smoluchowski)','No computed electric field 1 found')
        END IF
        IF (DIM .GE. 2) THEN
           EField2 => VariableGet( Model % Variables, 'Electric Field 2' )
           IF (ASSOCIATED(EField2)) THEN
              electricField(2) = EField2%Values(EField2%Perm(NodeNumber))
              ElectricFieldExists = .TRUE.
!           ELSE
!              CALL WARN('electrokinetics (helmholtz_smoluchowski)','No computed electric field 2 found')
           END IF
        END IF
        IF (DIM .GE. 3) THEN
           EField3 => VariableGet( Model % Variables, 'Electric Field 3' )
           IF (ASSOCIATED(EField3)) THEN
              electricField(3) = EField3%Values(EField3%Perm(NodeNumber))
              ElectricFieldExists = .TRUE.
!           ELSE
!              CALL WARN('electrokinetics (helmholtz_smoluchowski)','No computed electric field 3 found')
           END IF
        END IF
     ELSE         
        WRITE(Message,'(a,a,a,i3)' ) 'Unknown entry, ', ElectricFieldMethod,&
             ',for keyword >Electric Field< for Equation no.', eq_id
        CALL WARN('electrokinetics (helmholtz_smoluchowski)',Message)
        ElectricFieldExists = .FALSE.
        hs_velocity = 0.0D00        
     END IF
  END IF
  Model % CurrentElement => BoundaryElement  ! restore correct pointer
  !---------------------------------------------
  ! compute the Helmholtz-Smoluchowski velocity
  !---------------------------------------------
  IF (ElectricFieldExists) THEN     
     norm_electricField = SUM(electricField(1:3)*Normal(1:3))
     tang_electricField(1:3)=0.0d00   
     DO i=1,DIM
        tang_electricField(i) = electricField(i) - norm_electricField*Normal(i)
     END DO  
     IF (CalcMobility) THEN
        eoMobility = (zetapotential * dielectricConstant * vacuumPerm)/ viscosity
     END IF
     hs_velocity = SUM(tang_electricField(1:3)*Tangent(1:3))*eoMobility
  END IF
END FUNCTION helmholtz_smoluchowski


! ******************************************************************************
!  Joule heat source as a function of electric field
! ******************************************************************************
FUNCTION getJouleHeat( Model, NodeNumber, realDummy ) RESULT(jouleHeat)
!DEC$ATTRIBUTES DLLEXPORT :: getJouleHeat
  USE Types
  USE Lists
  USE CoordinateSystems
!
  IMPLICIT NONE
! external variables
  TYPE(Model_t) :: Model
  INTEGER :: NodeNumber
  REAL(KIND=dp) :: realDummy, jouleHeat
! internal variables and parameters
  INTEGER, TARGET :: NodeNumberTarget(1)
  INTEGER, DIMENSION(:), POINTER :: NodeNumberArray
  REAL(KIND=dp) :: dummyArray(1), elConductivity, density, electricField(3), electricField_square
  INTEGER :: body_id, material_id, eq_id, DIM
  CHARACTER(LEN=MAX_NAME_LEN) :: ElectricFieldMethod
  LOGICAL :: GotIt, ElectricFieldExists
  TYPE(Element_t), POINTER :: Parent
  TYPE(ValueList_t), POINTER :: Material
  TYPE(Variable_t), POINTER :: EField1, EField2,EField3 


  DIM = CoordinateSystemDimension()
! provide arrays to let the ListGetReal/Integer function 
! work with just a nodal value to be read in
! -------------------------------------------------------
  NodeNumberTarget(1) = NodeNumber
  NodeNumberArray => NodeNumberTarget
!---------------------End of Header section ------------------------------------
  !-----------------------------------------------------------------
  ! get element info
  !-----------------------------------------------------------------
  body_id = Model % CurrentElement % BodyId
  eq_id = ListGetInteger( Model % Bodies(body_id) % Values,'Equation', &
       minv=1,maxv=Model % NumberOfEquations )
  material_id = ListGetInteger( Model % Bodies(body_id) % Values, 'Material', &
       minv=1, maxv=Model % NumberOFMaterials)
  Material => Model % Materials(material_id) % Values
  IF (.NOT. ASSOCIATED(Material)) THEN
     WRITE(Message, '(a,i3)' )'No Material found for body-id ', body_id
     CALL WARN('electrokinetics (getJouleHeat)',Message)
     jouleHeat = 0.0D00
     RETURN
  END IF
  !-----------------------------------------------------------------
  ! get material parameters
  !-----------------------------------------------------------------
  dummyArray = ListGetReal( Material, &
       'Electric Conductivity', 1, NodeNumberArray, GotIt )
  IF (.NOT. GotIt) THEN
     WRITE(Message, '(a,i3)' )&
          'No value for keyword >Electric Conductivity< found in Material section ',&
          material_id
     CALL WARN('electrokinetics (getJouleHeat)',Message)
     jouleHeat = 0.0D00
     RETURN
  ELSE
     elConductivity = dummyArray(1)
  END IF
  dummyArray = ListGetReal( Material,'Density', 1, NodeNumberArray, GotIt )
  IF (.NOT. GotIt) THEN
     WRITE(Message, '(a,i3)' )'No value for keyword >Density< found in Material section ',&
          material_id 
     CALL WARN('electrokinetics (getJouleHeat)',Message)
     CALL WARN('electrokinetics (getJouleHeat)','setting reference density to 1')
     density = 1.0D00
  ELSE
     density = dummyArray(1) 
  END IF
  !-----------------------------------------------------------------
  ! get electric field
  !-----------------------------------------------------------------
  ElectricFieldExists = .FALSE.
  ElectricFieldMethod = ListGetString( Model % Equations(eq_id) % Values, 'Electric Field', GotIt)
  IF ( .NOT.GotIt ) THEN 
     WRITE(Message,'(a,i3)' )&
          'No entry (constant,computed) for keyword >Electric Field<  defined in Equation no.',&
          eq_id
     CALL WARN('electrokinetics (getJouleHeat)',Message)
     CALL WARN('electrokinetics (getJouleHeat)','No Joule heating will be computed')
     ElectricFieldExists = .FALSE.
  ELSE 
     IF ( ElectricFieldMethod == 'constant') THEN ! read field components from Material section
        dummyArray =  ListGetReal( Material, 'Electric Field 1', 1, NodeNumberArray, GotIt )
        IF (.NOT. GotIt) THEN 
           electricField(1) = 0.0d00
        ELSE
           electricField(1) = dummyArray(1) 
           ElectricFieldExists = (ElectricFieldExists .OR. GotIt)
        END IF
        dummyArray =  ListGetReal( Material, 'Electric Field 2', 1, NodeNumberArray, GotIt )
        IF (.NOT. GotIt) THEN 
           electricField(2) = 0.0d00
        ELSE
           electricField(2) = dummyArray(1)
           ElectricFieldExists = (ElectricFieldExists .OR. GotIt) 
        END IF
        dummyArray =  ListGetReal( Material, 'Electric Field 3', 1, NodeNumberArray, GotIt )
        IF (.NOT. GotIt) THEN 
           electricField(3) = 0.0d00
        ELSE
           electricField(3) = dummyArray(1) 
           ElectricFieldExists = (ElectricFieldExists .OR. GotIt)
        END IF
        IF (.NOT. ElectricFieldExists) THEN
           WRITE(Message,'(a,i3)' )'No external electric field component found in Material',&
                material_id, ' although defined as constant'
           CALL INFO('electrokinetics (getJouleHeat)',Message,level=4)
        END IF
     ELSE IF ( ElectricFieldMethod == 'computed') THEN ! get Electric Field from Electrostatic Solver
        electricField = 0.0d00
        EField1 => VariableGet( Model % Variables, 'Electric Field 1' )
        IF (ASSOCIATED(EField1)) THEN
           electricField(1) = EField1%Values(EField1%Perm(NodeNumber))
           ElectricFieldExists = .TRUE.
!        ELSE
!           CALL WARN('electrokinetics (getJouleHeat)','No computed electric field 1 found')
        END IF
        IF (DIM .GE. 2) THEN
           EField2 => VariableGet( Model % Variables, 'Electric Field 2' )
           IF (ASSOCIATED(EField2)) THEN
              electricField(2) = EField2%Values(EField2%Perm(NodeNumber))
              ElectricFieldExists = .TRUE.
!           ELSE
!              CALL WARN('electrokinetics (getJouleHeat)','No computed electric field 2 found')
           END IF
        END IF
        IF (DIM .GE. 3) THEN
           EField3 => VariableGet( Model % Variables, 'Electric Field 3' )
           IF (ASSOCIATED(EField3)) THEN
              electricField(3) = EField3%Values(EField3%Perm(NodeNumber))
              ElectricFieldExists = .TRUE.
!           ELSE
!              CALL WARN('electrokinetics (getJouleHeat)','No computed electric field 3 found')
           END IF
        END IF
     ELSE         
        WRITE(Message,'(a,a,a,i3)' ) 'Unknown entry, ', ElectricFieldMethod,&
             ',for keyword >Electric Field< for Equation no.', eq_id
        CALL WARN('electrokinetics (getJouleHeat)',Message)
        ElectricFieldExists = .FALSE.
     END IF
  END IF

  IF (ElectricFieldExists) THEN
     electricField_square = SUM(electricField(1:3)*electricField(1:3))
     jouleHeat = elConductivity*electricField_square/density
  ELSE
     jouleHeat = 0.0D00
  END IF
END FUNCTION getJouleHeat




