!/*****************************************************************************
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
! ****************************************************************************/
!
!/*****************************************************************************
! *
! *            Module Author: Peter R�back
! *
! *                  Address: CSC - Scientific Computing Ltd.
! *                           Tekniikantie 15 a D, Box 405
! *                           02101 Espoo, Finland
! *                           Tel. +358 0 457 2080
! *                           Telefax: +358 0 457 2302
! *                    EMail: Peter.Raback@csc.fi
! *
! *                     Date: 20 Nov 2001
! *
! *               Modified by: 
! *                     EMail: 
! *
! *      Date of modification: 
! *
! ****************************************************************************/


!------------------------------------------------------------------------------
SUBROUTINE SaveScalars( Model,Solver,dt,TransientSimulation )
  !DEC$ATTRIBUTES DLLEXPORT :: SaveScalars
!------------------------------------------------------------------------------
!******************************************************************************
!
!  This subroutine saves scalar values to a matrix.
!
!  ARGUMENTS:
!
!  TYPE(Model_t) :: Model,  
!     INPUT: All model information (mesh, materials, BCs, etc...)
!
!  TYPE(Solver_t) :: Solver
!     INPUT: Linear & nonlinear equation solver options
!
!  REAL(KIND=dp) :: dt,
!     INPUT: Timestep size for time dependent simulations
!
!  LOGICAL :: TransientSimulation
!     INPUT: Steady state or transient simulation
!
!******************************************************************************
  USE DefUtils

  IMPLICIT NONE
!------------------------------------------------------------------------------
  TYPE(Solver_t), TARGET :: Solver
  TYPE(Model_t) :: Model
  REAL(KIND=dp) :: dt
  LOGICAL :: TransientSimulation
!------------------------------------------------------------------------------
! Local variables
!------------------------------------------------------------------------------
  CHARACTER(LEN=MAX_NAME_LEN), PARAMETER :: DefaultScalarsFile = 'scalars.dat'


  TYPE(ValueList_t), POINTER :: Lst
  TYPE(Variable_t), POINTER :: Var, OldVar
  TYPE(Mesh_t), POINTER :: Mesh
  TYPE(Element_t),POINTER :: CurrentElement
  TYPE(Nodes_t) :: ElementNodes
  LOGICAL :: SubroutineVisited=.FALSE.,MovingMesh, GotCoeff, &
      GotIt, GotOper, GotVar, ExactCoordinates, VariablesExist
  LOGICAL, ALLOCATABLE :: BoundaryFluxComputed(:)

  CHARACTER(LEN=MAX_NAME_LEN) :: MessageL

  REAL (KIND=DP) :: Minimum, Maximum, AbsMinimum, AbsMaximum, &
      Mean, Variance, Dist, x, y, z, Deviation, Vol, Intmean, intvar, &
      KineticEnergy, PotentialEnergy, FieldEnergy, & 
      IntSquare, LocalCoords(3), TempCoordinates(3)
  REAL (KIND=DP), ALLOCATABLE :: Values(:), CoordinateDist(:), &
      CoordinatesBasis(:,:), ElementValues(:), BoundaryFluxes(:)
  REAL (KIND=DP), POINTER :: PointCoordinates(:,:), LineCoordinates(:,:)
  INTEGER, POINTER :: PointIndex(:), CoordinateIndex(:), CoordinatesElemNo(:), &
      NodeIndexes(:)
  CHARACTER(LEN=MAX_NAME_LEN), ALLOCATABLE :: ValueNames(:)
  CHARACTER(LEN=MAX_NAME_LEN) :: ScalarsFile, ScalarNamesFile, &
      VariableName, ResultPrefix, Oper, Name, CoefficientName
  INTEGER :: i,j,k,l,q,n,MaxNo,No,NoPoints,NoCoordinates,NoLines,NumberOfVars,&
      NoDims, NoDofs, NoOper, NoElements, NoVar, DIM, MaxVars, NoEigenValues, Ind
  REAL (KIND=DP) :: CPUTime, CPUMemory, MINVAL, MAXVAL

  CHARACTER(LEN=MAX_NAME_LEN) :: VersionID = "$Id: SaveData.f90,v 1.113 2005/04/21 06:44:46 jpr Exp $"

  SAVE SubroutineVisited, NumberOfVars, MaxNo, &
      NoPoints, PointIndex, CoordinateIndex, CoordinateDist, ResultPrefix, &
      Values, ValueNames, NoCoordinates, ScalarsFile, ScalarNamesFile, &
      ExactCoordinates, CoordinatesElemNo, NoElements, ElementNodes, &
      ElementValues, CoordinatesBasis, PointCoordinates, NoDims, &
      BoundaryFluxes, BoundaryFluxComputed, VariablesExist, NoLines, &
      LineCoordinates

!------------------------------------------------------------------------------
!    Check if version number output is requested
!------------------------------------------------------------------------------
  IF ( .NOT. SubroutineVisited ) THEN
    IF ( ListGetLogical( GetSimulation(), 'Output Version Numbers', GotIt ) ) THEN
      CALL Info( 'SaveScalars', 'SaveData version:', Level = 0 ) 
      CALL Info( 'SaveScalars', VersionID, Level = 0 ) 
      CALL Info( 'SaveScalars', ' ', Level = 0 ) 
    END IF
  END IF
!------------------------------------------------------------------------------

  Mesh => Model % Meshes
  DO WHILE( ASSOCIATED(Mesh) )
    IF ( Mesh % OutputActive ) EXIT 
    Mesh => Mesh % Next
  END DO
  CALL SetCurrentMesh( Model, Mesh )

  DIM = CoordinateSystemDimension()
 

  IF(.NOT.SubroutineVisited) THEN
    
    ScalarsFile = ListGetString(Solver % Values,'Filename',GotIt )
    IF(.NOT. GotIt) ScalarsFile = DefaultScalarsFile
    
    ScalarNamesFile = TRIM(ScalarsFile) // '.' // TRIM("names")
    
    ResultPrefix = ListGetString(Solver % Values,'Scalars Prefix',GotIt )
    IF(.NOT. gotIt) ResultPrefix = 'res:'
    
    ! Find out how many variables should we saved
    NoVar = 0
    GotVar = .TRUE.
    VariablesExist = .FALSE.

    NULLIFY(OldVar)
    DO WHILE(GotVar)  
      NoVar = NoVar + 1
      IF(NoVar < 10) THEN
        WRITE (Name,'(A,I2)') 'Variable',NoVar
      ELSE
        WRITE (Name,'(A,I3)') 'Variable',NoVar    
      END IF

      VariableName = ListGetString( Solver % Values, TRIM(Name), GotVar )

      IF(TRIM(VariableName) == 'cpu time') CYCLE
      IF(TRIM(VariableName) == 'cpu memory') CYCLE

      IF(GotVar) THEN
        Var => VariableGet( Model % Variables, TRIM(VariableName), .TRUE.)
        IF ( .NOT. ASSOCIATED( Var ) )  THEN
          WRITE(MessageL,*) 'Requested object [',TRIM( VariableName ),'] not found.'
          CALL WARN('SaveSide',MessageL)
        ELSE
          OldVar => Var
        END IF
      END IF
    END DO

    NoVar = NoVar-1
    IF(NoVar > 0) VariablesExist = .TRUE.
  
    NoOper = 0
    NoPoints = 0
    NoPoints = 0
    NoCoordinates = 0
  
    ! Find out how many operators there are
    GotOper = .TRUE.
    DO WHILE(GotOper) 
      NoOper = NoOper + 1      
      IF(NoOper < 10) THEN
        WRITE (Name,'(A,I2)') 'Operator',NoOper
      ELSE
        WRITE (Name,'(A,I3)') 'Operator',NoOper    
      END IF
      Oper = ListGetString(Solver % Values,TRIM(Name),GotOper)
    END DO
    NoOper = NoOper-1
 
    LineCoordinates => ListGetConstRealArray(Solver % Values,'Polyline Coordinates',gotIt)
    IF(gotIt) THEN
      NoLines = SIZE(LineCoordinates,1) / 2
      NoDims = SIZE(LineCoordinates,2)
    ELSE 
      NoLines = 0
    END IF

    PointIndex => ListGetIntegerArray( Solver % Values,'Save Points',GotIt)
    IF ( gotIt ) NoPoints = SIZE(PointIndex)
    
    PointCoordinates => ListGetConstRealArray(Solver % Values,'Save Coordinates',gotIt)
    IF(gotIt) THEN
      NoCoordinates = SIZE(PointCoordinates,1)
      NoDims = SIZE(PointCoordinates,2)
    END IF
    ExactCoordinates = ListGetLogical(Solver % Values,'Exact Coordinates',GotIt )
    IF(.NOT. GotIt) ExactCoordinates = .FALSE.
    
    IF(ExactCoordinates) THEN
      NoElements = NoCoordinates 
      NoCoordinates = 0
    ELSE
      NoElements = 0
    END IF
    
    IF(NoCoordinates > 0) THEN
      ALLOCATE(CoordinateIndex(NoCoordinates))
      ALLOCATE(CoordinateDist(NoCoordinates))
    END IF
    
    n = Mesh % MaxElementNodes

    ALLOCATE( ElementNodes % x(n), ElementNodes % y(n), ElementNodes % z(n))

    IF(NoElements > 0) THEN
      ALLOCATE( CoordinatesElemNo(NoElements), ElementValues(n), &
          CoordinatesBasis(NoElements,n) )
    END IF


    ! Evaluate the maximum number of scalars for allocation

    ! First the external scalars
    MaxNo = 0
    Lst => Model % Simulation
    DO WHILE( ASSOCIATED( Lst ) )    
      IF ( Lst % Name(1:4) == TRIM(ResultPrefix) ) THEN
        MaxNo = MaxNo+1
      END IF
      Lst => Lst % Next
    END DO
    
    ! Then the values at exact points and elements 
    MaxVars = 0
    Var => Model % Variables
    DO WHILE( ASSOCIATED( Var ) )      
      IF ( .NOT. Var % Output .OR. SIZE(Var % Values) == 1 .OR. &
          (Var % DOFs /= 1 .AND. .NOT. ASSOCIATED(Var % EigenVectors)) ) THEN
        Var => Var % Next        
        CYCLE
      END IF      
      IF (ASSOCIATED (Var % EigenVectors)) THEN
        NoEigenValues = SIZE(Var % EigenValues) 
        MaxVars = MaxVars + Var % DOFs * NoEigenValues
      ELSE
        MaxVars = MaxVars + 1
      END IF
      Var => Var % Next      
    END DO
    MaxNo = MaxNo + MaxVars * (NoPoints + NoCoordinates + NoElements + 1)

    ! Then the derived data from the operators
    MaxNo = MaxNo + NoOper * (Model % NumberOfBCs + 1 + NoLines)

!------------------------------------------------------------------------------
!   Add eigenvalues on the list if not told to skip 'em
!------------------------------------------------------------------------------

    IF ( .NOT. ListGetLogical( Solver % Values, 'Skip Eigenvalues', GotIt ) ) THEN

      DO i = 1, Model % NumberOfSolvers
        
        IF ( Model % Solvers(i) % NOFEigenValues > 0 ) THEN
          DO j = 1, Model % Solvers(i) % NOFEigenValues

            k = Model % Solvers(i) % NOFEigenValues - j + 1

            IF ( ListGetLogical( Solver % Values, &
                'Save Eigen Frequencies', GotIt ) ) THEN

              WRITE( MessageL, '("res: Eigen frequency ", I2, " [Hz]")' ) k
              IF ( REAL( Model % Solvers(i) % Variable % EigenValues(k)) > 0 ) THEN
                CALL ListAddConstReal( Model % Simulation, MessageL, &
                    SQRT(REAL( Model % Solvers(i) % Variable % EigenValues(k)))/(2*PI))
              ELSE
                CALL ListAddConstReal( Model % Simulation, MessageL, -1.0d0 )
              END IF
            ELSE

              WRITE( MessageL, '("res: Eigenvalue ", I2)' ) k
              CALL ListAddConstReal( Model % Simulation, &
                  MessageL, REAL( Model % Solvers(i) % Variable % EigenValues(k)) )
            
            END IF

          END DO
          MaxNo = MaxNo + Model % Solvers(i) % NOFEigenValues
        END IF

      END DO

    END IF

!------------------------------------------------------------------------------

    ALLOCATE( Values( MaxNo), ValueNames( MaxNo), &
        BoundaryFluxes(MAX(Model % NumberOfBCs, NoLines) ), &
        BoundaryFluxComputed(MAX(Model % NumberOfBCs, NoLines)) )

  END IF

  MovingMesh = ListGetLogical(Solver % Values,'Moving Mesh',GotIt )
  
  IF(.NOT.SubroutineVisited .OR. MovingMesh) THEN
    
    ! Find the indexes of minimum distances
    IF(NoCoordinates > 0) THEN
      
      CoordinateDist = HUGE(Dist)
      DO i=1,Model % NumberOfNodes
        x = Mesh % Nodes % x(i)
        y = Mesh % Nodes % y(i)
        z = Mesh % Nodes % z(i)
        
        DO j=1,NoCoordinates
          Dist = (x-PointCoordinates(j,1))**2.0 + &
              (y-PointCoordinates(j,2))**2.0
          IF(NoDims == 3) THEN
            Dist = Dist + (z-PointCoordinates(j,3))**2.0
          END IF
          IF(Dist < CoordinateDist(j)) THEN
            CoordinateDist(j) = Dist
            CoordinateIndex(j) = i
          END IF
        END DO
      END DO
    END IF


    ! Write the value at the given coordinate points, really.
    ! Thus, find the point j's element and the local coordinates
    IF(NoElements > 0) THEN

      CoordinatesBasis = 0.0d0
      
      DO j=1,NoElements

        ! Go through all old model bulk elements (could use quadrant tree!)
        DO k=1,Mesh % NumberOfBulkElements

          CurrentElement => Mesh % Elements(k)
          n = CurrentElement % TYPE % NumberOfNodes
          NodeIndexes => CurrentElement % NodeIndexes
          
          ElementNodes % x(1:n) = Mesh % Nodes % x(NodeIndexes)
          ElementNodes % y(1:n) = Mesh % Nodes % y(NodeIndexes)
          ElementNodes % z(1:n) = Mesh % Nodes % z(NodeIndexes)
          
          TempCoordinates = 0.0d0
          DO i = 1, NoDims
            TempCoordinates(i) = PointCoordinates(j,i)
          END DO

          IF ( PointInElement( CurrentElement, ElementNodes, &
              TempCoordinates, LocalCoords ) ) EXIT
          ! PointInElement requires z-coordinate for the point
        END DO       
        
        IF ( k > Mesh % NumberOfBulkElements ) THEN
          WRITE( MessageL, * ) 'Coordinate was not found in any of the elements!',j
          CALL Warn( 'SaveScalars', MessageL )
          CoordinatesElemNo(j) = 1          
          CoordinatesBasis(j,:) = 0.0d0
        ELSE
          CoordinatesElemNo(j) = k
          ElementValues(1:n) = 0.0d0
          DO q=1,N
            ElementValues(q) = 1.0d0
            CoordinatesBasis(j,q) = InterpolateInElement( CurrentElement, ElementValues, &
                LocalCoords(1), LocalCoords(2), LocalCoords(3) )
            ElementValues(q) = 0.0d0
          END DO
        END IF
        
      END DO
    END IF
  END IF
    

  CALL Info( 'SaveScalars', '-----------------------------------------', Level=4 )
  WRITE( MessageL, * ) 'Saving scalar values to file ', TRIM(ScalarsFile)
  CALL Info( 'SaveScalars', MessageL, Level=4 )
  CALL Info( 'SaveScalars', '-----------------------------------------', Level=4 )

  Values = 0.0d0

  ! Read the scalars defined in other modules
  No = 0
  Lst => Model % Simulation
  DO WHILE( ASSOCIATED( Lst ) )    
    IF ( Lst % Name(1:4) == TRIM(ResultPrefix) ) THEN
      No = No+1
      Values(No) = Lst % Fvalues(1,1,1)
      ValueNames(No) = Lst % Name
    END IF
    Lst => Lst % Next
  END DO
   

  GotVar = .TRUE.
  NULLIFY(OldVar)
  NoVar = 0
  
  ! Go through the variables and compute the desired statistical data

  IF(VariablesExist) THEN
    DO WHILE(GotVar .OR. GotOper)
 
      GotOper = .FALSE.
      NULLIFY(Var)
      
      NoVar = NoVar + 1

      IF(NoVar < 10) THEN 
        WRITE (Name,'(A,I2)') 'Variable',NoVar
      ELSE
        WRITE (Name,'(A,I3)') 'Variable',NoVar
      END IF
      
      VariableName = ListGetString( Solver % Values, TRIM(Name), GotVar )

      IF(GotVar) THEN

        ! Check first two special case with no variables on the list
        IF(TRIM(VariableName) == 'cpu time') THEN
          No = No + 1
          Values(No) = CPUTime()
          ValueNames(No) = 'value: cpu time from start (s)'
          CYCLE        
        END IF

        IF(TRIM(VariableName) == 'cpu memory') THEN
          No = No + 1
          Values(No) = CPUMemory()
          ValueNames(No) = 'value: maximum memory usage (kb)'
          CYCLE        
        END IF

        Var => VariableGet( Model % Variables, TRIM(VariableName) )
        IF ( .NOT. ASSOCIATED( Var ) )  THEN
          Var => OldVar
          IF ( .NOT. ASSOCIATED( Var ) ) THEN
            CALL Warn('SaveData','The desired variable does not exist!')
            CYCLE
          END IF
        END IF

      ELSE
        IF(ASSOCIATED(OldVar)) Var => OldVar
      END IF

      IF(.NOT. ASSOCIATED(Var)) CYCLE 

      IF(SIZE(Var % Values) == 1) THEN
        IF(.NOT. GotVar) CYCLE
        No = No + 1
        Values(No) = Var % Values(1)
        ValueNames(No) = 'value: '//TRIM(VariableName)//' scalar variable'
        CYCLE
      END IF

      OldVar => Var        
      NoOper = NoVar 
      
      IF(NoOper < 10) THEN
        WRITE (Name,'(A,I2)') 'Operator',NoOper
      ELSE
        WRITE (Name,'(A,I3)') 'Operator',NoOper    
      END IF

      Oper = ListGetString(Solver % Values,TRIM(Name),GotOper)

      IF ( GotOper ) THEN

        No = No + 1
        
        SELECT CASE(Oper)

        CASE ('dofs') 
          Values(No) = 1.0d0 * SIZE(Var % Values)
          ValueNames(No) = TRIM(Oper)//': '//TRIM(VariableName)        
          
        CASE ('max','min','max abs','min abs','mean','variance') 
          Values(No) = VectorStatistics(Var,Oper)
          ValueNames(No) = TRIM(Oper)//': '//TRIM(VariableName)
          
        CASE ('deviation')
          Values(No) = VectorMeanDeviation(Var,Oper)
          ValueNames(No) = TRIM(Oper)//': '//TRIM(VariableName)
          
        CASE ('volume','int mean','int variance','potential energy',&
              'diffusive energy','convective energy')
          IF(NoOper < 10) THEN
            WRITE (Name,'(A,I2)') 'Coefficient',NoOper
          ELSE
            WRITE (Name,'(A,I3)') 'Coefficient',NoOper    
          END IF
          CoefficientName = ListGetString(Solver % Values,TRIM(Name),GotCoeff )

          Values(No) = BulkIntegrals(Var, Oper, GotCoeff, CoefficientName)
          ValueNames(No) = TRIM(Oper)//': '//TRIM(VariableName)
         
        CASE ('diffusive flux','convective flux','area')
          IF(NoOper < 10) THEN
            WRITE (Name,'(A,I2)') 'Coefficient',NoOper
          ELSE
            WRITE (Name,'(A,I3)') 'Coefficient',NoOper    
          END IF
          CoefficientName = ListGetString(Solver % Values,TRIM(Name),GotCoeff )
          
          BoundaryFluxComputed = .FALSE.
          BoundaryFluxes = 0.0d0         

          CALL BoundaryIntegrals(Var, Oper, GotCoeff, CoefficientName,&
              BoundaryFluxes,BoundaryFluxComputed)          

          No = No -1 
          DO j=1,Model % NumberOfBCs
            IF(BoundaryFluxComputed(j)) THEN
              No = No + 1
              WRITE (Name,'(A,A,A,A,I2)') TRIM(Oper),': ',TRIM(VariableName),' over bc',j
              Values(No) = BoundaryFluxes(j)
              ValueNames(No) = TRIM(Name)
            END IF
          END DO

          IF(TRIM(Oper) /= 'area') THEN
            No = No + 1
            WRITE (Name,'(A,A,A,A)') 'min ',TRIM(Oper),': ',TRIM(VariableName)
            Values(No) = MINVAL
            ValueNames(No) = TRIM(Name)

            No = No + 1
            WRITE (Name,'(A,A,A,A)') 'max ',TRIM(Oper),': ',TRIM(VariableName)
            Values(No) = MAXVAL
            ValueNames(No) = TRIM(Name)
          END IF
          
          IF(NoLines > 0) THEN
            BoundaryFluxComputed = .FALSE.
            BoundaryFluxes = 0.0d0         
            
            CALL PolylineIntegrals(Var, Oper, GotCoeff, CoefficientName,&
                BoundaryFluxes,BoundaryFluxComputed)          
            
            DO j=1,NoLines
              IF(BoundaryFluxComputed(j)) THEN
                No = No + 1
                WRITE (Name,'(A,A,A,A,I2)') TRIM(Oper),': ',TRIM(VariableName),' over polyline',j
                Values(No) = BoundaryFluxes(j)
                ValueNames(No) = TRIM(Name)
              END IF
            END DO
          END IF

        CASE DEFAULT 

          No = No - 1
          WRITE (MessageL,'(A,A)') 'Unknown operator: ',TRIM(Oper)
          CALL WARN('SaveScalars',MessageL)
          
        END SELECT

      END IF
    END DO
  END IF

  
  ! Get the info at node points
  DO k=1,NoPoints+NoCoordinates

    IF(k <= NoPoints) THEN
      l = PointIndex(k)
    ELSE
      l = CoordinateIndex(k-NoPoints)
    END IF
    
    Var => Model % Variables
    DO WHILE( ASSOCIATED( Var ) )

      IF ( .NOT. Var % Output .OR. SIZE(Var % Values) == 1 .OR. &
          (Var % DOFs /= 1 .AND. .NOT. ASSOCIATED(Var % EigenVectors)) ) THEN
        Var => Var % Next        
        CYCLE
      END IF
      
      IF (ASSOCIATED (Var % EigenVectors)) THEN
        NoEigenValues = SIZE(Var % EigenValues) 
        DO j=1,NoEigenValues
          DO i=1,Var % DOFs

            Ind = l
            IF ( ASSOCIATED(Var % Perm) ) THEN
              Ind = Var % Perm(Ind)
            END IF
            IF(.NOT. (Ind > 0)) CYCLE

            No = No + 1
            Values(No) = Var % EigenVectors(j,Var%Dofs*(Ind-1)+i)
            
            IF(Var % DOFs == 1) THEN
              WRITE(ValueNames(No),'("value: Eigen",I2," ",A," at node ",I7)') j,TRIM(Var % Name),l
            ELSE
              WRITE(ValueNames(No),'("value: Eigen",I2," ",A,I2," at node ",I7)') j,TRIM(Var % Name),i,l
            END IF
          END DO
        END DO

      ELSE           
        Ind = l
        IF ( ASSOCIATED(Var % Perm) ) Ind = Var % Perm(Ind)
        IF(.NOT. (Ind > 0)) CYCLE
        
        No = No + 1
        Values(No) = Var % Values(Ind)          
        
        WRITE(ValueNames(No),'("value: ",A," at node ",I7)') TRIM(Var % Name),l
      END IF

      Var => Var % Next      
    END DO
  END DO
  
  ! Get the info at exact coordinates within elements
  DO k=1,NoElements        
    l = CoordinatesElemNo(k)
    CurrentElement => Mesh % Elements(l)
    n = CurrentElement % TYPE % NumberOfNodes
    NodeIndexes => CurrentElement % NodeIndexes
    
    Var => Model % Variables
    DO WHILE( ASSOCIATED( Var ) )
      
      IF ( .NOT. Var % Output .OR. SIZE(Var % Values) == 1 .OR. &
          (Var % DOFs /= 1 .AND. .NOT. ASSOCIATED(Var % EigenVectors)) ) THEN
        Var => Var % Next        
        CYCLE
      END IF
      
      IF(.NOT. ASSOCIATED(Var)) CYCLE

      IF (ASSOCIATED (Var % EigenVectors)) THEN
        NoEigenValues = SIZE(Var % EigenValues) 
        DO j=1,NoEigenValues
          DO i=1,Var % DOFs
            IF (ASSOCIATED(Var % Perm) ) THEN
              IF(.NOT. ALL(Var % Perm(NodeIndexes(1:n)) > 0)) CYCLE
              ElementValues(1:n) = Var % EigenVectors(j,Var%Dofs*(Var % Perm(NodeIndexes(1:n))-1)+i)
            ELSE
              ElementValues(1:n) = Var % EigenVectors(j,Var%Dofs*(NodeIndexes(1:n)-1)+i)
            END IF
            
            No = No + 1
            Values(No) = SUM( CoordinatesBasis(k,1:n) * ElementValues(1:n) ) 
            
            IF(Var % DOFs == 1) THEN
              WRITE(ValueNames(No),&
                  '("value: Eigen",I2," ",A," in element ",I7)') j,TRIM(Var % Name),l
            ELSE
              WRITE(ValueNames(No),&
                  '("value: Eigen",I2," ",A,I2," in element ",I7)') j,TRIM(Var % Name),i,l
            END IF
          END DO
        END DO
      ELSE           
        IF ( ASSOCIATED(Var % Perm) ) THEN
          ElementValues(1:n) = Var % Values(Var % Perm(NodeIndexes(1:n)))
          IF(.NOT. ALL(Var % Perm(NodeIndexes(1:n)) > 0)) CYCLE
        ELSE
          ElementValues(1:n) = Var % Values(NodeIndexes(1:n))
        END IF

        No = No + 1
        Values(No) = SUM( CoordinatesBasis(k,1:n) * ElementValues(1:n) ) 

        WRITE(ValueNames(No),'("value: ",A," in element ",I7)') TRIM(Var % Name),l
      END IF
      Var => Var % Next      
    END DO
  END DO

  MaxNo = No

!  /*�And finally SAVE the scalars into a file */

  IF(.NOT. SubroutineVisited .OR. MovingMesh) THEN 
    OPEN (10, FILE=ScalarNamesFile)
    WRITE(10,*) 'Variables in columns of matrix: '//TRIM(ScalarsFile)
    DO No=1,MaxNo 
      WRITE(10,'(I4,": ",A)') No,TRIM(ValueNames(No))
    END DO
    CLOSE(10)
  END IF


  IF(SubroutineVisited) THEN 
    OPEN (10, FILE=ScalarsFile,POSITION='APPEND')
  ELSE 
    OPEN (10,FILE=ScalarsFile)
  END IF
  DO No=1,MaxNo
    WRITE (10,'(ES20.12E3)',advance='no') Values(No)
  END DO
  WRITE(10,'(A)') ' '
  CLOSE(10)

  DO No=1,MaxNo 
    CALL ListAddConstReal(Model % Simulation,TRIM(ValueNames(No)),Values(No))
  END DO

  SubroutineVisited = .TRUE.

!------------------------------------------------------------------------------


CONTAINS

  FUNCTION VectorStatistics(Var,OperName) RESULT (operx)

    TYPE(Variable_t), POINTER :: Var
    CHARACTER(LEN=MAX_NAME_LEN) :: OperName
    REAL(KIND=dp) :: operx
    REAL(KIND=dp) :: Minimum, Maximum, AbsMinimum, AbsMaximum, &
        Mean, Variance, sumx, sumxx, x, Variance2
    INTEGER :: Nonodes, i, j, k, l, NoDofs, sumi
    LOGICAL :: Initialized 

    Initialized = .FALSE.
    sumi = 0
    sumx = 0.0
    sumxx = 0.0

    NoDofs = Var % Dofs

    IF(NoDofs >= 1) THEN
      Nonodes = SIZE(Var % Values) / NoDofs
    END IF

    DO i=1,Nonodes
      j = i
      IF(ASSOCIATED(Var % Perm)) j = Var % Perm(i)
      IF(j > 0) THEN
        IF(NoDofs <= 1) THEN
          x = Var % Values(j)
        ELSE
          x = 0.0d0
          DO l=1,NoDofs
            x = x + Var % Values(NoDofs*(j-1)+l) ** 2.0
          END DO
          x = SQRT(x)
        END IF
        IF(.NOT. Initialized) THEN
          Initialized = .TRUE.
          Maximum = x
          Minimum = x
          AbsMaximum = x
          AbsMinimum = x
        END IF
        sumi = sumi + 1
        sumx = sumx + x
        sumxx = sumxx + x*x
        Maximum = MAX(x,Maximum)
        Minimum = MIN(x,Minimum)
        IF(ABS(x) > ABS(AbsMaximum) ) AbsMaximum = x
        IF(ABS(x) < ABS(AbsMinimum) ) AbsMinimum = x
      END IF
    END DO

    ! If there are no dofs avoid division by zero
    IF(sumi == 0) THEN
      operx = 0.0d0
      RETURN
    END IF

    Mean = sumx / sumi

    Variance2 = sumxx/sumi-Mean*Mean
    IF(Variance2 > 0.0d0) THEN
      Variance = SQRT(Variance2) 
    ELSE
      Variance = 0.0d0
    END IF

    SELECT CASE(OperName)
      
      CASE ('max')
      operx = Maximum

      CASE ('min')
      operx = Minimum

      CASE ('max abs')
      operx = AbsMaximum

      CASE ('min abs')
      operx = AbsMinimum

      CASE ('mean')
      operx = Mean

      CASE ('variance')
      operx = Variance

    CASE DEFAULT 
      CALL Warn('SaveScalars','Unknown statistical operator')

    END SELECT
      

  END FUNCTION VectorStatistics

!------------------------------------------------------------------------------

  FUNCTION VectorMeanDeviation(Var,OperName) RESULT (Deviation)

    TYPE(Variable_t), POINTER :: Var
    CHARACTER(LEN=MAX_NAME_LEN) :: OperName
    REAL(KIND=dp) :: Mean, Deviation
    REAL(KIND=dp) :: sumx, sumdx, x, dx
    INTEGER :: Nonodes, i, j, k, NoDofs, sumi

    NoDofs = Var % Dofs
    IF(NoDofs >= 1) THEN
      Nonodes = SIZE(Var % Values) / NoDofs
    END IF

    sumi = 0
    sumx = 0.0
    DO i=1,Nonodes
      j = i
      IF(ASSOCIATED(Var % Perm)) j = Var % Perm(i)
      IF(j > 0) THEN
        IF(NoDofs <= 1) THEN
          x = Var % Values(j)
        ELSE
          x = 0.0d0
          DO k=1,NoDofs
            x = x + Var % Values(NoDofs*(j-1)+k) ** 2.0
          END DO
          x = SQRT(x)
        END IF
        sumi = sumi + 1
        sumx = sumx + x
      END IF
    END DO

    sumi = MAX(sumi,1)
    Mean = sumx / sumi

    sumi = 0
    sumdx = 0.0
    DO i=1,Nonodes
      j = i
      IF(ASSOCIATED(Var % Perm)) j = Var % Perm(i)
      IF(j > 0) THEN
        IF(NoDofs <= 1) THEN
          x = Var % Values(j)
        ELSE
          x = 0.0d0
          DO k=1,NoDofs
            x = x + Var % Values(NoDofs*(j-1)+k) ** 2.0
          END DO
          x = SQRT(x)
        END IF
        dx = ABS(x-Mean)
        sumi = sumi + 1
        sumdx = sumdx + dx
      END IF
    END DO
    
    sumi = MAX(sumi,1)
    Deviation = sumdx / sumi

  END FUNCTION VectorMeanDeviation

!------------------------------------------------------------------------------

  FUNCTION BulkIntegrals(Var, OperName, GotCoeff, CoeffName) RESULT (operx)
    TYPE(Variable_t), POINTER :: Var
    CHARACTER(LEN=MAX_NAME_LEN) :: OperName, CoeffName
    LOGICAL :: GotCoeff
    REAL(KIND=dp) :: operx, vol
    
    INTEGER :: t, hits
    TYPE(Element_t), POINTER :: Element
 
    REAL(KIND=dp) :: SqrtMetric,Metric(3,3),Symb(3,3,3),dSymb(3,3,3,3)
    REAL(KIND=dp) :: Basis(n),dBasisdx(n,3),ddBasisddx(n,3,3)
    REAL(KIND=dp) :: EnergyTensor(3,3,Model % MaxElementNodes),&
        EnergyCoeff(Model % MaxElementNodes) 
    REAL(KIND=dp) :: SqrtElementMetric,U,V,W,S,A,L,C(3,3),x,y,z
    REAL(KIND=dp) :: func, coeff, integral1, integral2, Grad(3), CoeffGrad(3)
    REAL(KIND=DP), POINTER :: Pwrk(:,:,:)
    LOGICAL :: Stat
    
    INTEGER :: i,j,k,p,q,DIM,NoDofs
    
    TYPE(GaussIntegrationPoints_t) :: IntegStuff

    hits = 0
    integral1 = 0._dp
    integral2 = 0._dp
    vol = 0._dp
    EnergyCoeff = 1.0d0

    NoDofs = Var % Dofs

    DIM = CoordinateSystemDimension()


    DO t = 1, Mesh % NumberOfBulkElements + Mesh % NumberOfBoundaryElements

      IF(t == Mesh % NumberOfBulkElements + 1 .AND. hits > 0) GOTO 10

      Element => Mesh % Elements(t)
      Model % CurrentElement => Mesh % Elements(t)
      n = Element % TYPE % NumberOfNodes
      NodeIndexes => Element % NodeIndexes
      
      IF ( Element % TYPE % ElementCode == 101 ) CYCLE
      IF ( ANY(Var % Perm(NodeIndexes(1:n)) == 0) ) CYCLE
      
      hits = hits + 1
      
      ElementNodes % x(1:n) = Mesh % Nodes % x(NodeIndexes(1:n))
      ElementNodes % y(1:n) = Mesh % Nodes % y(NodeIndexes(1:n))
      ElementNodes % z(1:n) = Mesh % Nodes % z(NodeIndexes(1:n))


      SELECT CASE(OperName)

        CASE('diffusive energy') 
        k = ListGetInteger( Model % Bodies( Element % BodyId ) % Values, &
            'Material', GotIt, minv=1, maxv=Model % NumberOfMaterials )

        CALL ListGetRealArray( Model % Materials(k) % Values, &
            TRIM(CoeffName), Pwrk, n, NodeIndexes, gotIt )

        EnergyTensor = 0.0d0
        IF(GotIt) THEN
          IF ( SIZE(Pwrk,1) == 1 ) THEN
            DO i=1,3
              EnergyTensor( i,i,1:n ) = Pwrk( 1,1,1:n )
            END DO
          ELSE IF ( SIZE(Pwrk,2) == 1 ) THEN
            DO i=1,MIN(3,SIZE(Pwrk,1))
              EnergyTensor(i,i,1:n) = Pwrk(i,1,1:n)
            END DO
          ELSE
            DO i=1,MIN(3,SIZE(Pwrk,1))
              DO j=1,MIN(3,SIZE(Pwrk,2))
                EnergyTensor( i,j,1:n ) = Pwrk(i,j,1:n)
              END DO
            END DO
          END IF
        ELSE 
          DO i=1,3          
            EnergyTensor(i,i,1:n) = 1.0d0
          END DO
        END IF

        CASE ('potential energy','convective energy','volume')
        k = ListGetInteger( Model % Bodies( Element % BodyId ) % Values, &
            'Material', GotIt, minv=1, maxv=Model % NumberOfMaterials )

        IF(GotCoeff) THEN
          EnergyCoeff = ListGetReal( Model % Materials(k) % Values, &
              TRIM(CoeffName), n, NodeIndexes(1:n), gotIt )
          IF(.NOT. GotIt) EnergyCoeff(1:n) = 1.0d0
        END IF

      END SELECT

!------------------------------------------------------------------------------
!    Numerical integration
!------------------------------------------------------------------------------
      IntegStuff = GaussPoints( Element )
      
      DO i=1,IntegStuff % n
        U = IntegStuff % u(i)
        V = IntegStuff % v(i)
        W = IntegStuff % w(i)
!------------------------------------------------------------------------------
!        Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
        stat = ElementInfo( Element,ElementNodes,U,V,W,SqrtElementMetric, &
            Basis,dBasisdx,ddBasisddx,.FALSE. )
!------------------------------------------------------------------------------
!      Coordinatesystem dependent info
!------------------------------------------------------------------------------
        s = 1.0
        IF ( CurrentCoordinateSystem() /= Cartesian ) THEN
          x = SUM( ElementNodes % x(1:n)*Basis(1:n) )
          y = SUM( ElementNodes % y(1:n)*Basis(1:n) )
          z = SUM( ElementNodes % z(1:n)*Basis(1:n) )
          s = 2*PI
        END IF
        
        CALL CoordinateSystemInfo( Metric,SqrtMetric,Symb,dSymb,x,y,z )
        
        s = s * SqrtMetric * SqrtElementMetric * IntegStuff % s(i)
        vol =  vol + S

        SELECT CASE(OperName)
          
          CASE ('volume')
          coeff = SUM( EnergyCoeff(1:n) * Basis(1:n))
          integral1 = integral1 + coeff * S

          CASE ('int mean')
          func = SUM( Var % Values(Var % Perm(NodeIndexes(1:n))) * Basis(1:n) )
          integral1 = integral1 + S * func 

          CASE ('int variance')
          func = SUM( Var % Values(Var % Perm(NodeIndexes(1:n))) * Basis(1:n) )
          integral1 = integral1 + S * func 
          integral2 = integral2 + S * func**2.0 

          CASE ('diffusive energy')
          CoeffGrad = 0.0d0
          DO j = 1, DIM
            Grad(j) = SUM( dBasisdx(1:n,j) *  Var % Values(Var % Perm(NodeIndexes(1:n))) )
            DO k = 1, DIM
              CoeffGrad(j) = CoeffGrad(j) + SUM( EnergyTensor(j,k,1:n) * Basis(1:n) ) * &
                  SUM( dBasisdx(1:n,k) * Var % Values(Var % Perm(NodeIndexes(1:n))) )
            END DO
          END DO
          
          integral1 = integral1 + s * SUM( Grad(1:DIM) * CoeffGrad(1:DIM) )

          CASE ('convective energy')
          func = SUM( Var % Values(Var % Perm(NodeIndexes(1:n))) * Basis(1:n) )
          coeff = SUM( EnergyCoeff(1:n) * Basis(1:n))

          IF(NoDofs == 1) THEN
            func = SUM( Var % Values(Var % Perm(NodeIndexes(1:n))) * Basis(1:n) )
            integral1 = integral1 + s * coeff * func**2.0d0
          ELSE
            func = 0.0d0
            DO j=1,MIN(DIM,NoDofs)
              func = SUM( Var % Values(NoDofs*(Var % Perm(NodeIndexes(1:n))-1)+j) * Basis(1:n) )
              integral1 = integral1 + s * coeff * func**2.0d0
            END DO
          END IF

          CASE ('potential energy')

          func = SUM( Var % Values(Var % Perm(NodeIndexes(1:n))) * Basis(1:n) )
          coeff = SUM( EnergyCoeff(1:n) * Basis(1:n))
          integral1 = integral1 + s * coeff * func

        CASE DEFAULT 
          CALL Warn('SaveScalars','Unknown statistical operator')

        END SELECT

      END DO

    END DO


10  CONTINUE 
    
    operx = 0.0d0
    IF(hits == 0) RETURN

    SELECT CASE(OperName)
      
      CASE ('volume')
      operx = integral1
      
      CASE ('int mean')
      operx = integral1 / vol        

      CASE ('int variance')
      operx = SQRT(integral2/vol-(integral1/vol)**2.0d0)

      CASE ('diffusive energy')
      operx = 0.5d0 * integral1

      CASE ('convective energy')
      operx = 0.5d0 * integral1

      CASE ('potential energy')
      operx = integral1
      
    END SELECT


  END FUNCTION BulkIntegrals
!------------------------------------------------------------------------------


  SUBROUTINE BoundaryIntegrals(Var, OperName, GotCoeff, &
      CoeffName, fluxes, fluxescomputed)

    TYPE(Variable_t), POINTER :: Var
    CHARACTER(LEN=MAX_NAME_LEN) :: OperName, CoeffName
    LOGICAL :: GotCoeff
    REAL(KIND=dp) :: fluxes(:)
    LOGICAL :: fluxescomputed(:)
    
    INTEGER :: t, FluxBody
    TYPE(Element_t), POINTER :: Element, Parent    
    TYPE(ValueList_t), POINTER :: Material
    REAL(KIND=dp) :: SqrtMetric,Metric(3,3),Symb(3,3,3),dSymb(3,3,3,3)
    REAL(KIND=dp) :: Basis(Model % MaxElementNodes),dBasisdx(Model % MaxElementNodes,3),&
        ddBasisddx(Model % MaxElementNodes,3,3), ParentBasis(Model % MaxElementNodes),&
        ParentdBasisdx(Model % MaxElementNodes,3),EnergyTensor(3,3,Model % MaxElementNodes),&
        EnergyCoeff(Model % MaxElementNodes)
    REAL(KIND=dp) :: SqrtElementMetric,U,V,W,up,vp,wp,S,A,L,C(3,3),x,y,z
    REAL(KIND=dp) :: func, coeff, area, Normal(3), Flow(3), flux
    REAL(KIND=DP), POINTER :: Pwrk(:,:,:)
    INTEGER, POINTER :: ParentIndexes(:), PermIndexes(:)

    LOGICAL :: Stat, Permutated    
    INTEGER :: i,j,k,p,q,DIM,bc,NoDofs,pn,hits
    TYPE(GaussIntegrationPoints_t) :: IntegStuff
    TYPE(Nodes_t) :: ParentNodes

    n = Model % MaxElementNodes


    ALLOCATE(ParentNodes % x(n), ParentNodes % y(n), ParentNodes % z(n), PermIndexes(n) )

    area = 0.0d0
    hits = 0
    MINVAL = HUGE(MINVAL)
    MAXVAL = -HUGE(MAXVAL)

    NoDofs = Var % Dofs
    Permutated = ASSOCIATED(Var % Perm)
    DO i=1,3          
      EnergyTensor(i,i,:) = 1.0d0
    END DO

    SELECT CASE(OperName)
      
      CASE('diffusive flux') 
      IF(NoDofs /= 1) THEN
        CALL Warn('SaveScalars','diffusive flux & NoDofs /= 1?')
        RETURN
      END IF

      CASE ('convective flux')
      IF(NoDofs /= 1 .AND. NoDofs < DIM) THEN
        CALL Warn('SaveScalars','convective flux & NoDofs < DIM?')
        RETURN
      END IF
      
      CASE ('area')

    CASE DEFAULT 
      CALL Warn('SaveScalars','Unknown statistical operator')

    END SELECT

    DIM = CoordinateSystemDimension()

    fluxes = 0.0d0


    DO t = Mesh % NumberOfBulkElements+1, Mesh % NumberOfBulkElements &
        + Mesh % NumberOfBoundaryElements

      Element => Mesh % Elements(t)
      Model % CurrentElement => Mesh % Elements(t)

      IF ( Element % TYPE % ElementCode == 101 ) CYCLE

      n = Element % TYPE % NumberOfNodes
      NodeIndexes => Element % NodeIndexes

      IF(Permutated) THEN
        PermIndexes(1:n) = Var % Perm(NodeIndexes(1:n))
        IF (ANY( PermIndexes(1:n) == 0)) CYCLE
      ELSE
        PermIndexes(1:n) = NodeIndexes(1:n)        
      END IF

      DO bc=1, Model % NumberOfBCs

        IF ( Model % BCs(bc) % Tag /= Element % BoundaryInfo % Constraint ) CYCLE
        IF(.NOT. ListGetLogical(Model % BCs(bc) % Values,'Flux Integrate',gotIt ) ) CYCLE

        hits = hits + 1
                 
        ElementNodes % x(1:n) = Mesh % Nodes % x(NodeIndexes(1:n))
        ElementNodes % y(1:n) = Mesh % Nodes % y(NodeIndexes(1:n))
        ElementNodes % z(1:n) = Mesh % Nodes % z(NodeIndexes(1:n))

        FluxBody = ListGetInteger( Model % BCs(bc) % Values, &
             'Flux Integrate Body', gotIt ) 
        IF ( GotIt ) THEN
           IF ( Element % BoundaryInfo % LBody == FluxBody ) THEN
              Parent => Element % BoundaryInfo % Left
           ELSEIF ( Element % BoundaryInfo % RBody == FluxBody ) THEN
              Parent => Element % BoundaryInfo % Right
           ELSE
              WRITE( MessageL, * ) 'No such flux integrate body on bc ', &
                   Element % BoundaryInfo % Constraint
              CALL Fatal( 'SaveScalars', MessageL )
           END IF
        ELSE        
           Parent => ELement % BoundaryInfo % Left
           stat = ASSOCIATED( Parent )

           IF(Permutated) THEN
              IF(stat) stat = ALL(Var % Perm(Parent % NodeIndexes) > 0)
          
              IF ( .NOT. stat ) THEN
                 Parent => ELement % BoundaryInfo % Right
            
                 stat = ASSOCIATED( Parent )
                 IF(stat) stat = ALL(Var % Perm(Parent % NodeIndexes) > 0)
              END IF
           END IF
           IF ( .NOT. stat )  CALL Fatal( 'SaveScalars',&
                'No solution available for specified boundary' )
        END IF


        i = ListGetInteger( Model % Bodies(Parent % BodyId) % Values, 'Material', &
            minv=1, maxv=Model % NumberOFMaterials )
        Material => Model % Materials(i) % Values
        fluxescomputed(bc) = .TRUE.


        SELECT CASE(OperName)

          CASE('diffusive flux') 

          pn = Parent % TYPE % NumberOfNodes
          ParentIndexes => Parent % NodeIndexes

          ParentNodes % x(1:pn) = Mesh % Nodes % x(ParentIndexes(1:pn))
          ParentNodes % y(1:pn) = Mesh % Nodes % y(ParentIndexes(1:pn))
          ParentNodes % z(1:pn) = Mesh % Nodes % z(ParentIndexes(1:pn))

          GotIt = .FALSE.
          EnergyTensor = 0._dp

          IF(GotCoeff) THEN
            CALL ListGetRealArray( Material, CoeffName, Pwrk, &
                pn, ParentIndexes, gotIt )

            IF(GotIt) THEN
              IF ( SIZE(Pwrk,1) == 1 ) THEN
                DO i=1,3
                  EnergyTensor( i,i,1:pn ) = Pwrk( 1,1,1:pn )
                END DO
              ELSE IF ( SIZE(Pwrk,2) == 1 ) THEN
                DO i=1,MIN(3,SIZE(Pwrk,1))
                  EnergyTensor(i,i,1:pn) = Pwrk(i,1,1:pn)
                END DO
              ELSE
                DO i=1,MIN(3,SIZE(Pwrk,1))
                  DO j=1,MIN(3,SIZE(Pwrk,2))
                    EnergyTensor( i,j,1:pn ) = Pwrk(i,j,1:pn)
                  END DO
                END DO
              END IF
            END IF
          END IF

          IF(.NOT. GotIt) THEN
            DO i=1,3          
              EnergyTensor(i,i,1:pn) = 1.0d0
            END DO
          END IF

          CASE ('convective flux','area')
          EnergyCoeff(1:n) = ListGetReal( Material, CoeffName, n, NodeIndexes, gotIt )
          IF(.NOT. GotIt) EnergyCoeff(1:n) = 1.0d0
          
        END SELECT

!------------------------------------------------------------------------------
!    Numerical integration
!------------------------------------------------------------------------------
        IntegStuff = GaussPoints( Element )
        
        DO i=1,IntegStuff % n
          U = IntegStuff % u(i)
          V = IntegStuff % v(i)
          W = IntegStuff % w(i)
!------------------------------------------------------------------------------
!        Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
          stat = ElementInfo( Element,ElementNodes,U,V,W,SqrtElementMetric, &
              Basis,dBasisdx,ddBasisddx,.FALSE. )
!------------------------------------------------------------------------------
!      Coordinatesystem dependent info
!------------------------------------------------------------------------------
          x = SUM( ElementNodes % x(1:n)*Basis(1:n) )
          y = SUM( ElementNodes % y(1:n)*Basis(1:n) )
          z = SUM( ElementNodes % z(1:n)*Basis(1:n) )

          s = 1.0d0

          IF(.FALSE.) THEN
            IF ( CurrentCoordinateSystem() /= Cartesian ) THEN
              s = 2.0d0 * PI 
            END IF
            CALL CoordinateSystemInfo( Metric,SqrtMetric,Symb,dSymb,x,y,z )
            s = s * SqrtMetric * SqrtElementMetric * IntegStuff % s(i)
          ELSE
            IF ( CurrentCoordinateSystem() /= Cartesian ) THEN
              s = 2.0d0 * PI * x 
            END IF
            s = s * SqrtElementMetric * IntegStuff % s(i)
          END IF

          area =  area + s
          
          Normal = NormalVector( Element,ElementNodes,U,V,.TRUE. )

          
          SELECT CASE(OperName)
            
            CASE ('diffusive flux')

            CALL GlobalToLocal( up,vp,wp,x,y,z,Parent,ParentNodes )

            stat = ElementInfo( Parent,ParentNodes,Up,Vp,Wp,SqrtElementMetric, &
                ParentBasis,ParentdBasisdx,ddBasisddx,.FALSE. )

            Flow = 0.0d0

            DO j = 1, DIM
              DO k = 1, DIM
                IF(Permutated) THEN
                  Flow(j) = Flow(j) + SUM( EnergyTensor(j,k,1:pn) * ParentBasis(1:pn) ) * &
                      SUM( ParentdBasisdx(1:pn,k) * Var % Values(Var % Perm(ParentIndexes(1:pn))) )
                ELSE
                  Flow(j) = Flow(j) + SUM( EnergyTensor(j,k,1:pn) * ParentBasis(1:pn) ) * &
                      SUM( ParentdBasisdx(1:pn,k) * Var % Values(ParentIndexes(1:pn)) ) 
                END IF
              END DO
            END DO

            flux = SUM(Normal(1:DIM) * Flow(1:DIM))
            MINVAL = MIN(flux,MINVAL)
            MAXVAL = MAX(flux,MAXVAL)

            fluxes(bc) = fluxes(bc) + s * flux

            CASE ('convective flux')

            coeff = SUM( EnergyCoeff(1:n) * Basis(1:n))

            IF(NoDofs == 1) THEN
              func = SUM( Var % Values(PermIndexes(1:n)) * Basis(1:n) )
              fluxes(bc) = fluxes(bc) + s * coeff * func
              MINVAL = MIN(MINVAL, coeff*func)
              MAXVAL = MAX(MAXVAL, coeff*func)
            ELSE 
              DO j=1,DIM
                Flow(j) = coeff * SUM( Var % Values(NoDofs*(PermIndexes(1:n)-1)+j) * Basis(1:n) )
              END DO
              fluxes(bc) = fluxes(bc) + s * coeff * SUM(Normal * Flow)
              MINVAL = MIN(MINVAL, coeff * SUM(Normal * Flow))
              MAXVAL = MAX(MAXVAL, coeff * SUM(Normal * Flow))
            END IF
 
            CASE ('area')
            coeff = SUM( EnergyCoeff(1:n) * Basis(1:n))
            fluxes(bc) = fluxes(bc) + s * coeff 
            
         END SELECT
          
        END DO

      END DO

    END DO

    DEALLOCATE( ParentNodes % x, ParentNodes % y, ParentNodes % z, PermIndexes )


  END SUBROUTINE BoundaryIntegrals
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------


  SUBROUTINE PolylineIntegrals(Var, OperName, GotCoeff, &
      CoeffName, fluxes, fluxescomputed)

    TYPE(Variable_t), POINTER :: Var
    CHARACTER(LEN=MAX_NAME_LEN) :: OperName, CoeffName
    LOGICAL :: GotCoeff
    REAL(KIND=dp) :: fluxes(:)
    LOGICAL :: fluxescomputed(:)
    
    INTEGER :: t
    TYPE(Element_t), TARGET :: SideElement
    TYPE(Element_t), POINTER :: Element, Parent    
    TYPE(ValueList_t), POINTER :: Material
    REAL(KIND=dp) :: SqrtMetric,Metric(3,3),Symb(3,3,3),dSymb(3,3,3,3)
    REAL(KIND=dp) :: Basis(Model % MaxElementNodes),dBasisdx(Model % MaxElementNodes,3),&
        ddBasisddx(Model % MaxElementNodes,3,3), ParentBasis(Model % MaxElementNodes),&
        ParentdBasisdx(Model % MaxElementNodes,3),EnergyTensor(3,3,Model % MaxElementNodes),&
        EnergyCoeff(Model % MaxElementNodes) 
    REAL(KIND=dp) :: SqrtElementMetric,U,V,W,up,vp,wp,S,A,L,C(3,3),x,y,z,dx,dy,dz,ds,dsmax
    REAL(KIND=dp) :: func, coeff, area, Normal(3), Flow(3), x0, y0, z0, pos(2)
    REAL(KIND=DP), POINTER :: Pwrk(:,:,:)
    INTEGER, POINTER :: ParentIndexes(:), PermIndexes(:), SideIndexes(:), OnLine(:,:)

    LOGICAL :: Stat, Permutated, Inside    
    INTEGER :: i,j,k,p,q,DIM,bc,NoDofs,pn,Line, NoSides, Side, NodeNumber, LineNode(2)
    TYPE(GaussIntegrationPoints_t) :: IntegStuff
    TYPE(Nodes_t) :: ParentNodes, LineNodes, SideNodes


    n = Model % MaxElementNodes

    ALLOCATE(ParentNodes % x(n), ParentNodes % y(n), ParentNodes % z(n), PermIndexes(n) )
    ALLOCATE(SideNodes % x(n), SideNodes % y(n), SideNodes % z(n), SideIndexes(n)  )
    ALLOCATE(LineNodes % x(n), LineNodes % y(n), LineNodes % z(n)  )
    ALLOCATE(OnLine(Mesh % NumberOfNodes,2))


    area = 0.0

    NoDofs = Var % Dofs
    Permutated = ASSOCIATED(Var % Perm)
    DO i=1,3          
      EnergyTensor(i,i,:) = 1.0d0
    END DO

    SELECT CASE(OperName)
      
      CASE('diffusive flux') 
      IF(NoDofs /= 1) THEN
        CALL Warn('SaveScalars','diffusive flux & NoDofs /= 1?')
        RETURN
      END IF

      CASE ('convective flux')
      IF(NoDofs /= 1 .AND. NoDofs < DIM) THEN
        CALL Warn('SaveScalars','convective flux & NoDofs < DIM?')
        RETURN
      END IF
      
      CASE ('area')

    CASE DEFAULT 
      CALL Warn('SaveScalars','Unknown physical operator')

    END SELECT

    DIM = CoordinateSystemDimension()
    IF(DIM < 3) THEN
      LineNodes % z = 0.0d0
      SideNodes % z(1:2) = 0.0d0
    END IF

    fluxes = 0.0d0
    SideElement % TYPE => GetElementType( 202, .FALSE.)
    SideElement % Bdofs = 0
    Element => SideElement

!   /* Go through the line segments */
    DO Line = 1,NoLines 
      LineNodes % x(1:2) = LineCoordinates(2*Line-1:2*Line,1) 
      LineNodes % y(1:2) = LineCoordinates(2*Line-1:2*Line,2) 
      IF(DIM == 3) LineNodes % z(1:2) = LineCoordinates(2*Line-1:2*Line,3) 
      OnLine = 0

      DO t = 1, Mesh % NumberOfBulkElements 
        
        Parent => Mesh % Elements(t)
        Model % CurrentElement => Mesh % Elements(t)

        NoSides = Parent % TYPE % ElementCode / 100  
        IF(NoSides < 3 .OR. NoSides > 4) CYCLE
        
        pn = Parent % TYPE % NumberOfNodes
        ParentIndexes => Parent % NodeIndexes

        ParentNodes % x(1:pn) = Mesh % Nodes % x(ParentIndexes(1:pn))
        ParentNodes % y(1:pn) = Mesh % Nodes % y(ParentIndexes(1:pn))
        ParentNodes % z(1:pn) = Mesh % Nodes % z(ParentIndexes(1:pn))          
        
        IF(Permutated) THEN
          PermIndexes(1:pn) = Var % Perm(ParentIndexes(1:pn))
          IF (ANY( PermIndexes(1:pn) == 0)) CYCLE
        ELSE
          PermIndexes(1:pn) = ParentIndexes(1:pn)        
        END IF

        NodeNumber = 0

        DO Side = 1, NoSides

          SideIndexes(1) = ParentIndexes(Side)
          SideIndexes(2) = ParentIndexes(MOD(Side,NoSides)+1)
          
          SideNodes % x(1:2) = Mesh % Nodes % x(SideIndexes(1:2))
          SideNodes % y(1:2) = Mesh % Nodes % y(SideIndexes(1:2))
          IF(DIM == 3) SideNodes % z(1:2) = Mesh % Nodes % z(SideIndexes(1:2))
  
          CALL LineIntersectionCoords(SideNodes,LineNodes,Inside,x0,y0,z0,u)

          IF(.NOT. Inside) CYCLE

          NodeNumber = NodeNumber + 1        
          ElementNodes % x(NodeNumber) = x0
          ElementNodes % y(NodeNumber) = y0
          ElementNodes % z(NodeNumber) = z0
          pos(NodeNumber) = u

        END DO

        IF(NodeNumber == 0) CYCLE

        IF(NodeNumber > 2) THEN
          CALL Warn('PolylineIntergrals','There should not be more than 2 intersections!')
          CYCLE
        END IF

        !---------------------------------------------------------------------------
        ! If there is only one intersection the other end of the node must lie
        ! inside the element. Assume that the line is long compared to the 
        ! element and thus the end may be easily 
        IF(NodeNumber == 1) THEN
          IF(pos(1) < 0.5d0) THEN
            i = 1
            pos(2) = 0.0
          ELSE
            i = 2
            pos(2) = 1.0
          END IF
          x0 = LineNodes % x(i)
          y0 = LineNodes % y(i)
          z0 = LineNodes % z(i)            

          ElementNodes % x(2) = LineNodes % x(i)
          ElementNodes % y(2) = LineNodes % y(i)
          ElementNodes % z(2) = LineNodes % z(i)            
        END IF

        IF(ABS(pos(1)-pos(2)) < 1.0d-8) CYCLE

        !-----------------------------------------------------------------------------
        ! Change the order of nodes so that the normal always points to the same direction          
        IF(pos(1) < pos(2)) THEN
          ElementNodes % x(2) = ElementNodes % x(1)
          ElementNodes % y(2) = ElementNodes % y(1)
          ElementNodes % z(2) = ElementNodes % z(1)
          ElementNodes % x(1) = x0
          ElementNodes % y(1) = y0
          ElementNodes % z(1) = z0           
        END IF
        
        !--------------------------------------------------------------------------------
        ! The following avoids the cases where the line goes exactly at the element 
        ! interface and therefore the flux would be computed twice

        dx = ElementNodes % x(1) - ElementNodes % x(2)
        dy = ElementNodes % y(1) - ElementNodes % y(2)
        dsmax = SQRT(dx*dx+dy*dy)
        LineNode = 0

        DO i=1,Parent % TYPE % ElementCode / 100 
          DO j=1,2
            dx = ParentNodes % x(i) - ElementNodes % x(j)
            dy = ParentNodes % y(i) - ElementNodes % y(j)
            ds = SQRT(dx*dx+dy*dy)
            IF(ds < 1.0d-4 * dsmax) LineNode(j) = ParentIndexes(i)
          END DO
        END DO

        IF(ALL(LineNode(1:2) > 0)) THEN
          IF(ANY(OnLine(LineNode(1),:) == LineNode(2))) CYCLE
          IF(ANY(OnLine(LineNode(2),:) == LineNode(1))) CYCLE

          IF(OnLine(LineNode(1),1) == 0) THEN
            OnLine(LineNode(1),1) = LineNode(2)
          ELSE IF(OnLine(LineNode(1),2) == 0) THEN
            OnLine(LineNode(1),2) = LineNode(2)
          ELSE
            CALL Warn('PolylineIntegrate','This should never happen')
          END IF
          
          IF(OnLine(LineNode(2),1) == 0) THEN
            OnLine(LineNode(2),1) = LineNode(1)
          ELSE IF(OnLine(LineNode(2),2) == 0) THEN
            OnLine(LineNode(2),2) = LineNode(1)
          ELSE
            CALL Warn('PolylineIntegrate','This should never happen')
          END IF
        END IF


        
        i = ListGetInteger( Model % Bodies(Parent % BodyId) % Values, 'Material', &
            minv=1, maxv=Model % NumberOFMaterials )
        Material => Model % Materials(i) % Values
        fluxescomputed(Line) = .TRUE.
        
        
        SELECT CASE(OperName)
          
          CASE('diffusive flux') 
          
          IF(GotCoeff) THEN
            CALL ListGetRealArray( Material, CoeffName, Pwrk, &
                pn, ParentIndexes, gotIt )
            
            EnergyTensor = 0._dp
            IF(GotIt) THEN
              IF ( SIZE(Pwrk,1) == 1 ) THEN
                DO i=1,3
                  EnergyTensor( i,i,1:pn ) = Pwrk( 1,1,1:pn )
                END DO
              ELSE IF ( SIZE(Pwrk,2) == 1 ) THEN
                DO i=1,MIN(3,SIZE(Pwrk,1))
                  EnergyTensor(i,i,1:pn) = Pwrk(i,1,1:pn)
                END DO
              ELSE
                DO i=1,MIN(3,SIZE(Pwrk,1))
                  DO j=1,MIN(3,SIZE(Pwrk,2))
                    EnergyTensor( i,j,1:pn ) = Pwrk(i,j,1:pn)
                  END DO
                END DO
              END IF
            ELSE 
              DO i=1,3          
                EnergyTensor(i,i,1:pn) = 1.0d0
              END DO
            END IF
          END IF
          
          CASE ('convective flux','area')
          EnergyCoeff(1:n) = ListGetReal( Material, CoeffName, pn, ParentIndexes, gotIt )
          IF(.NOT. GotIt) EnergyCoeff(1:pn) = 1.0d0
          
        END SELECT

!------------------------------------------------------------------------------
!    Numerical integration
!------------------------------------------------------------------------------

        IntegStuff = GaussPoints( Element )
        
        DO i=1,IntegStuff % n
          U = IntegStuff % u(i)
          V = IntegStuff % v(i)
          W = IntegStuff % w(i)

!------------------------------------------------------------------------------
!        Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
          stat = ElementInfo( Element,ElementNodes,U,V,W,SqrtElementMetric, &
              Basis,dBasisdx,ddBasisddx,.FALSE. )
          
          x = SUM( ElementNodes % x(1:n) * Basis(1:n) )
          y = SUM( ElementNodes % y(1:n) * Basis(1:n) )
          z = SUM( ElementNodes % z(1:n) * Basis(1:n) )
!------------------------------------------------------------------------------
!      Coordinatesystem dependent info
!------------------------------------------------------------------------------

          s = 1.0d0

          IF(.FALSE.) THEN
            IF(CurrentCoordinateSystem() /= Cartesian ) s = 2.0 * PI 
            CALL CoordinateSystemInfo( Metric,SqrtMetric,Symb,dSymb,x,y,z )
            s = s * SqrtMetric * SqrtElementMetric * IntegStuff % s(i)
          ELSE
            IF(CurrentCoordinateSystem() /= Cartesian ) s = 2.0 * PI * x
            s = s * SqrtElementMetric * IntegStuff % s(i)            
          END IF
     
          area =  area + s          
          Normal = NormalVector( Element,ElementNodes,U,V,.FALSE. )

!------------------------------------------------------------------------------
!      Because the intersection nodes do not really exist the field variables 
!      must be avaluated using the nodes of the parent element.
!------------------------------------------------------------------------------
            
          CALL GlobalToLocal( up,vp,wp,x,y,z,Parent,ParentNodes )
          
          stat = ElementInfo( Parent,ParentNodes,Up,Vp,Wp,SqrtElementMetric, &
              ParentBasis,ParentdBasisdx,ddBasisddx,.FALSE. )
          
          
          SELECT CASE(OperName)
            
            CASE ('diffusive flux')
            
            Flow = 0.0d0
            DO j = 1, DIM
              DO k = 1, DIM
                IF(Permutated) THEN
                  Flow(j) = Flow(j) + SUM( EnergyTensor(j,k,1:pn) * ParentBasis(1:pn) ) * &
                      SUM( ParentdBasisdx(1:pn,k) * Var % Values(Var % Perm(ParentIndexes(1:pn))) )
                ELSE
                  Flow(j) = Flow(j) + SUM( EnergyTensor(j,k,1:pn) * ParentBasis(1:pn) ) * &
                      SUM( ParentdBasisdx(1:pn,k) * Var % Values(ParentIndexes(1:pn)) ) 
                END IF
              END DO
            END DO
            
            fluxes(Line) = fluxes(Line) + s * SUM(Normal(1:DIM) * Flow(1:DIM))
            
            
            CASE ('convective flux')
            
            coeff = SUM( EnergyCoeff(1:pn) * Basis(1:pn))
            
            IF(NoDofs == 1) THEN
              func = SUM( Var % Values(PermIndexes(1:pn)) * Basis(1:pn) )
              fluxes(Line) = fluxes(Line) + s * coeff * func
            ELSE 
              DO j=1,DIM
                Flow(j) = coeff * SUM( Var % Values(NoDofs*(PermIndexes(1:pn)-1)+j) * Basis(1:pn) )
              END DO
              fluxes(Line) = fluxes(Line) + s * coeff * SUM(Normal * Flow)
            END IF
            
            CASE ('area')            
            
            coeff = SUM( EnergyCoeff(1:pn) * Basis(1:pn))
            fluxes(Line) = fluxes(Line) + s * coeff 
            
          END SELECT

        END DO 

      END DO

    END DO

    DEALLOCATE( ParentNodes % x, ParentNodes % y, ParentNodes % z, PermIndexes, &
        SideNodes % x, SideNodes % y, SideNodes % z, SideIndexes, &
        LineNodes % x, LineNodes % y, LineNodes % z, OnLine)

  END SUBROUTINE 
!------------------------------------------------------------------------------


  SUBROUTINE LineIntersectionCoords(Plane,Line,Inside,x0,y0,z0,frac)
! This subroutine tests whether the line segment goes through the current
! face of the element. 

    TYPE(Nodes_t) :: Plane, Line
    LOGICAL :: Inside
    REAL (KIND=dp) :: x0, y0, z0, frac

    REAL (KIND=dp) :: A(3,3),B(3),C(3),eps=1.0d-6,detA,absA

    Inside = .FALSE.
    
    ! In 2D the intersection is between two lines
    A(1,1) = Line % x(2) - Line % x(1)
    A(2,1) = Line % y(2) - Line % y(1)
    A(1,2) = Plane % x(1) - Plane % x(2)
    A(2,2) = Plane % y(1) - Plane % y(2)

    detA = A(1,1)*A(2,2)-A(1,2)*A(2,1)
    absA = SUM(ABS(A(1,1:2))) * SUM(ABS(A(2,1:2)))
    
    IF(ABS(detA) <= eps * absA + 1.0d-20) RETURN
    
    B(1) = Plane % x(1) - Line % x(1) 
    B(2) = Plane % y(1) - Line % y(1) 
    
    CALL InvertMatrix( A,2 )
    C(1:2) = MATMUL(A(1:2,1:2),B(1:2))
    
    IF(ANY(C(1:2) < 0.0) .OR. ANY(C(1:2) > 1.0d0)) RETURN
    
    Inside = .TRUE.
    frac = C(1)
    X0 = Line % x(1) + C(1) * (Line % x(2) - Line % x(1))
    Y0 = Line % y(1) + C(1) * (Line % y(2) - Line % y(1))
    Z0 = Line % z(1) + C(1) * (Line % z(2) - Line % z(1))
    
  END SUBROUTINE LineIntersectionCoords
  
!------------------------------------------------------------------------------
END SUBROUTINE SaveScalars
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
! Saves line data in different formats.
! 1) Saves the 1D boundaries with keyword 'Save Line'
! 2) Saves the principle axis (This might be obsolite)
! 3) Saves polyline defined by coordinates in 2D or 3D  
!------------------------------------------------------------------------------

SUBROUTINE SaveLine( Model,Solver,dt,TransientSimulation )
!DEC$ATTRIBUTES DLLEXPORT :: SaveLine

  USE Types
  USE Lists
  USE Integration
  USE ElementDescription
  USE SolverUtils
  USE MeshUtils
  USE DefUtils

  IMPLICIT NONE
!------------------------------------------------------------------------------
  TYPE(Solver_t) :: Solver
  TYPE(Model_t) :: Model
  REAL(KIND=dp) :: dt
  LOGICAL :: TransientSimulation
!------------------------------------------------------------------------------
! Local variables
!------------------------------------------------------------------------------
  CHARACTER(LEN=MAX_NAME_LEN), PARAMETER :: DefaultSideFile = 'sides.dat'

  CHARACTER(LEN=MAX_NAME_LEN) :: MessageL

  REAL (KIND=DP), ALLOCATABLE ::  Values(:), Basis(:)
  REAL (KIND=dp) :: daxisx, daxisy, daxisz, x, y, z, eps, IntersectEpsilon, f1, f2, fn, weight
  REAL (KIND=DP), POINTER :: PointCoordinates(:,:), PointFluxes(:,:), PointWeight(:)
  LOGICAL :: Stat, GotIt, SubroutineVisited = .FALSE., FileAppend, CalculateFlux, &
      SaveAxis(3), Inside, MovingMesh, IntersectEdge
  INTEGER :: i,j,k,l,n,m,t,DIM,mat_id, TimesVisited=0, SaveThis, PrevDoneTime=-1, &
      Side, SavedNodes, node, PrevIndex, SaveOrder, NoResults, &
      No, axis, maxboundary, NoDims, NoLines, NoAxis, Line, NoFaces, &
      NoEigenValues, IntersectCoordinate, ElemCorners, ElemDim, FluxBody
  INTEGER, ALLOCATABLE :: SavedIndex(:)
  INTEGER, POINTER :: NodeIndexes(:), NextIndexes(:)
  TYPE(Variable_t), POINTER :: Var
  TYPE(Mesh_t), POINTER :: Mesh
  TYPE(ValueList_t), POINTER :: Material
  TYPE(Nodes_t) :: ElementNodes, LineNodes
  TYPE(Element_t), POINTER   :: CurrentElement, NextElement
  CHARACTER(LEN=MAX_NAME_LEN) :: SideFile, SideNamesFile, VarName, CondName
  CHARACTER(LEN=MAX_NAME_LEN), ALLOCATABLE :: ValueNames(:)
  CHARACTER(LEN=MAX_NAME_LEN) :: VersionID = "$Id: SaveData.f90,v 1.113 2005/04/21 06:44:46 jpr Exp $"

  LOGICAL :: cand

  SAVE SubroutineVisited, TimesVisited, SavedIndex, ElementNodes, LineNodes, &
      Basis, NoResults, NoEigenValues, Values, PrevDoneTime

!------------------------------------------------------------------------------
!    Check if version number output is requested
!------------------------------------------------------------------------------
  IF ( .NOT. SubroutineVisited ) THEN
    IF ( ListGetLogical( GetSimulation(), 'Output Version Numbers', GotIt ) ) THEN
      CALL Info( 'SaveLine', 'SaveData version:', Level = 0 ) 
      CALL Info( 'SaveLine', VersionID, Level = 0 ) 
      CALL Info( 'SaveLine', ' ', Level = 0 ) 
    END IF
  END IF
!------------------------------------------------------------------------------

  Mesh => Model % Meshes
  DO WHILE( ASSOCIATED(Mesh) )
    IF (Mesh % OutputActive) EXIT 
    Mesh => Mesh % Next
  END DO

  CALL SetCurrentMesh( Model, Mesh )

  IF(.NOT. SubroutineVisited) THEN
    n = Mesh % MaxElementNodes
    ALLOCATE( ElementNodes % x(n), ElementNodes % y(n), ElementNodes % z(n), &
        LineNodes % x(2), LineNodes % y(2), LineNodes % z(2), &
        Basis(n), SavedIndex(Mesh % NumberOfNodes) )
  END IF

  DIM = CoordinateSystemDimension()

  IF(TransientSimulation .AND. PrevDoneTime /= Solver % DoneTime) THEN
    PrevDoneTime = Solver % DoneTime
    TimesVisited = 0
  END IF

  TimesVisited = TimesVisited + 1
  PrevIndex = 0
  SavedNodes = 0
  maxboundary = 0

  SideFile = ListGetString(Solver % Values,'Filename',GotIt )
  IF(.NOT. GotIt) SideFile = DefaultSideFile

  FileAppend = ListGetLogical(Solver % Values,'File Append',GotIt )
  MovingMesh = ListGetLogical(Solver % Values,'Moving Mesh',GotIt )

  IntersectEdge = ListGetLogical(Solver % Values,'Intersect Edge',GotIt )
  IF(IntersectEdge) THEN
    IntersectCoordinate = ListGetInteger(Solver % Values,'Intersect Coordinate')
    IntersectEpsilon = ListGetConstReal(Solver % Values,'Intersect Epsilon')
  ELSE 
    IntersectCoordinate = 0
  END IF

  CalculateFlux = ListGetLogical(Solver % Values,'Save Heat Flux',GotIt )
  IF(.NOT. CalculateFlux) THEN
    CalculateFlux = ListGetLogical(Solver % Values,'Save Flux',GotIt )
  END IF

  IF(CalculateFlux) THEN
    VarName = ListGetString(Solver % Values,'Flux Variable',GotIt )
    IF(.NOT. gotIt) VarName = TRIM('Temperature')
    CondName = ListGetString(Solver % Values,'Flux Coefficient',GotIt )
    IF(.NOT. gotIt) CondName = TRIM('Heat Conductivity')
  END IF

  SaveAxis(1) = ListGetLogical(Solver % Values,'Save Axis',GotIt)
  IF(GotIt) THEN
    SaveAxis(2:3) = SaveAxis(1)
  ELSE
    SaveAxis(1) = ListGetLogical(Solver % Values,'Save Axis 1',GotIt)
    SaveAxis(2) = ListGetLogical(Solver % Values,'Save Axis 2',GotIt)
    SaveAxis(3) = ListGetLogical(Solver % Values,'Save Axis 3',GotIt)    
  END IF
  NoAxis = DIM

  PointCoordinates => ListGetConstRealArray(Solver % Values,'Polyline Coordinates',gotIt)
  IF(gotIt) THEN
    NoLines = SIZE(PointCoordinates,1) / 2
    NoDims = SIZE(PointCoordinates,2)
  ELSE 
    NoLines = 0
  END IF


  ! Calculate the number of entries for each node 
  IF(.NOT. SubroutineVisited) THEN
    NoResults = 0
    Var => Model % Variables

    DO WHILE( ASSOCIATED( Var ) )    
      
      IF ( .NOT. Var % Output .OR. SIZE(Var % Values) == 1 .OR. &
          (Var % DOFs /= 1 .AND. .NOT. ASSOCIATED(Var % EigenVectors)) ) THEN
        Var => Var % Next        
        CYCLE
      END IF

      IF (ASSOCIATED (Var % EigenVectors)) THEN
        NoEigenValues = SIZE(Var % EigenValues) 
        NoResults = NoResults + Var % Dofs * NoEigenValues
      ELSE 
        NoResults = NoResults + 1
      END IF
      Var => Var % Next      
    END DO

    IF ( CalculateFlux ) NoResults = NoResults + 3
    
    ALLOCATE( Values(NoResults) )
  END IF

  CALL Info( 'SaveLine', '-------------------------------------', Level=4 )
  WRITE( MessageL, * ) 'Saving line data to file ', TRIM(SideFile)
  CALL Info( 'SaveLine', MessageL, Level=4 )
  CALL Info( 'SaveLine', '-------------------------------------', Level=4 )

  IF(SubroutineVisited .AND. FileAppend) THEN 
    OPEN (10, FILE=SideFile,POSITION='APPEND')
  ELSE 
    OPEN (10,FILE=SideFile)
  END IF


!------------------------------------------------------------------------------
! Find out which nodes should be saved
!------------------------------------------------------------------------------
  SavedIndex = 0
  SavedNodes = 0
  DO t = 1,  Mesh % NumberOfBulkElements + Mesh % NumberOfBoundaryElements
    CurrentElement => Mesh % Elements(t)
    ElemCorners = CurrentElement % TYPE % ElementCode / 100
    IF(ElemCorners > 4) CYCLE

    n = CurrentElement % TYPE % NumberOfNodes
    NodeIndexes => CurrentElement % NodeIndexes

    SaveThis = 0
    IF(t <= Mesh % NumberOfBulkElements) THEN
      k = CurrentElement % BodyId
      IF(ListGetLogical( Model % Bodies(k) % Values,'Save Line', GotIt)) SaveThis = k
    ELSE
      DO k=1, Model % NumberOfBCs
        IF ( Model % BCs(k) % Tag /= CurrentElement % BoundaryInfo % Constraint ) CYCLE
        IF( ListGetLogical(Model % BCs(k) % Values,'Save Line',gotIt ) ) SaveThis = k
      END DO
    END IF
    IF(SaveThis == 0) CYCLE

    DO i=1,n
      j = NodeIndexes(i) 
      IF(SavedIndex(j) == 0) THEN
        SavedNodes = SavedNodes + 1
        SavedIndex(j) = SavedNodes
      END IF
    END DO
  END DO

!------------------------------------------------------------------------------
! Go through the sides and save the fluxes if requested 
!------------------------------------------------------------------------------


  IF(CalculateFlux) THEN
    ALLOCATE(PointFluxes(SavedNodes,3),PointWeight(SavedNodes))    
    PointFluxes = 0.0d0
    PointWeight = 0.0d0

    DO t = 1,  Mesh % NumberOfBulkElements + Mesh % NumberOfBoundaryElements
      
      CurrentElement => Mesh % Elements(t)
      
      ElemCorners = CurrentElement % TYPE % ElementCode / 100
      IF(ElemCorners > 4 .OR. ElemCorners < 2) CYCLE
      
      Model % CurrentElement => CurrentElement
      n = CurrentElement % TYPE % NumberOfNodes
      NodeIndexes => CurrentElement % NodeIndexes
      
      SaveThis = 0
      IF(t <= Mesh % NumberOfBulkElements) THEN
        k = CurrentElement % BodyId
        IF(ListGetLogical( Model % Bodies(k) % Values,'Save Line', GotIt)) SaveThis = k
        FluxBody = ListGetInteger( Model % Bodies(k) % Values,'Flux Integrate Body', gotIt ) 
      ELSE
        DO k=1, Model % NumberOfBCs
          IF ( Model % BCs(k) % Tag /= CurrentElement % BoundaryInfo % Constraint ) CYCLE
          IF( ListGetLogical(Model % BCs(k) % Values,'Save Line',gotIt ) ) SaveThis = k
          FluxBody = ListGetInteger( Model % BCs(k) % Values,'Flux Integrate Body', gotIt )         
        END DO
      END IF
      IF(SaveThis == 0) CYCLE
      
      ElementNodes % x(1:n) = Mesh % Nodes % x(NodeIndexes)
      ElementNodes % y(1:n) = Mesh % Nodes % y(NodeIndexes)
      ElementNodes % z(1:n) = Mesh % Nodes % z(NodeIndexes)
      
      DO i=1,n
        node = NodeIndexes(i)
        
        CALL BoundaryFlux( Model, node, VarName, CondName, f1, f2, fn, weight) 
        j = SavedIndex(node) 
        PointFluxes(j,1) = PointFluxes(j,1) + weight * f1
        PointFluxes(j,2) = PointFluxes(j,2) + weight * f2
        PointFluxes(j,3) = PointFluxes(j,3) + weight * fn
        PointWeight(j) = PointWeight(j) + weight
      END DO
      
    END DO
    
    DO i = 1,  Mesh % NumberOfNodes
      j = SavedIndex(i)
      IF(j == 0) CYCLE
      PointFluxes(j,1) = PointFluxes(j,1) / PointWeight(j)
      PointFluxes(j,2) = PointFluxes(j,2) / PointWeight(j)
      PointFluxes(j,3) = PointFluxes(j,3) / PointWeight(j)
    END DO

    DEALLOCATE(PointWeight)
  END IF


!------------------------------------------------------------------------------
! Go through the sides and save data in a chain format
!------------------------------------------------------------------------------

  DO t = 1,  Mesh % NumberOfBulkElements + Mesh % NumberOfBoundaryElements

    CurrentElement => Mesh % Elements(t)

    ElemCorners = CurrentElement % TYPE % ElementCode / 100
    IF(ElemCorners > 4) CYCLE

    Model % CurrentElement => CurrentElement
    n = CurrentElement % TYPE % NumberOfNodes
    NodeIndexes => CurrentElement % NodeIndexes

    SaveThis = 0
    IF(t <= Mesh % NumberOfBulkElements) THEN
      k = CurrentElement % BodyId
      IF(ListGetLogical( Model % Bodies(k) % Values,'Save Line', GotIt)) SaveThis = k
    ELSE
      DO k=1, Model % NumberOfBCs
        IF ( Model % BCs(k) % Tag /= CurrentElement % BoundaryInfo % Constraint ) CYCLE
        IF( ListGetLogical(Model % BCs(k) % Values,'Save Line',gotIt ) ) SaveThis = k
      END DO
    END IF
    IF(SaveThis == 0) CYCLE

    IF(t < Mesh % NumberOfBulkElements + Mesh % NumberOfBoundaryElements) THEN
      NextElement => Mesh % Elements(t+1)
      NextIndexes => NextElement % NodeIndexes
    END IF
    
    SaveOrder = 0
    
    IF(n > 1) THEN 
      ! Check if some of the indexes has already been saved 
      IF(PrevIndex /= 0) THEN
        IF(NodeIndexes(1) == PrevIndex) THEN
          SaveOrder = 1
        ELSE IF(NodeIndexes(2) == PrevIndex) THEN
          SaveOrder = -1
        END IF
      END IF
      
      ! If not then save both so that the first one starts the chain
      IF(SaveOrder == 0) THEN
        IF((NodeIndexes(1) == NextIndexes(1)) .OR. &
            (NodeIndexes(1) == NextIndexes(2))) THEN
          SaveOrder = -2
        ELSE 
          SaveOrder = 2
        END IF
      END IF
    END IF
      
    ElementNodes % x(1:n) = Mesh % Nodes % x(NodeIndexes)
    ElementNodes % y(1:n) = Mesh % Nodes % y(NodeIndexes)
    ElementNodes % z(1:n) = Mesh % Nodes % z(NodeIndexes)
    
    DO m=1,n
      IF(SaveOrder == 0) THEN 
        node = 1
      ELSE IF(SaveOrder == 2) THEN
        IF(m == 1) node = 1
        IF(m == n) node = 2
        IF(m > 1 .AND. m < n) node = m+1
      ELSE IF(SaveOrder == 1) THEN
        IF(m == 1) node = 0
        IF(m == n) node = 2
        IF(m > 1 .AND. m<n) node = m+1
      ELSE IF(SaveOrder == -2) THEN
        IF(m == 1) node = 2
        IF(m == n) node = 1
        IF(m > 1 .AND. m < n) node = m+1
      ELSE IF(SaveOrder == -1) THEN
        IF(m == 1) node = 0
        IF(m == n) node = 1
        IF(m > 1 .AND. m<n) node = m+1
      END IF
      
      IF(node == 0) CYCLE
      
      PrevIndex = NodeIndexes(node)
      SavedNodes = SavedNodes + 1
            
      IF(TransientSimulation) WRITE(10,'(I4)',ADVANCE='NO') Solver % DoneTime
      WRITE(10,'(I3,I3,I7)',ADVANCE='NO') TimesVisited,SaveThis,PrevIndex
      maxboundary = MAX(SaveThis,maxboundary) 
      
      Var => Model % Variables
      No = 0
      Values = 0.0d0
      
      DO WHILE( ASSOCIATED( Var ) )
        
        IF ( .NOT. Var % Output .OR. SIZE(Var % Values) == 1 .OR. &
            (Var % DOFs /= 1 .AND. .NOT. ASSOCIATED(Var % EigenVectors)) ) THEN
          Var => Var % Next        
          CYCLE
        END IF
        
        l = NodeIndexes(node)
        
        IF (ASSOCIATED (Var % EigenVectors)) THEN
          NoEigenValues = SIZE(Var % EigenValues) 
          DO j=1,NoEigenValues
            DO i=1,Var % DOFs
              IF ( ASSOCIATED(Var % Perm) ) l = Var % Perm(l)
              IF(l > 0) THEN 
                Values(No+(j-1)*Var%Dofs+i) = Var % EigenVectors(j,Var%Dofs*(l-1)+i)
              END IF
            END DO
          END DO          
          No = No + Var % Dofs * NoEigenValues
        ELSE           
          No = No + 1
          IF ( ASSOCIATED(Var % Perm) ) l = Var % Perm(l)
          IF(l > 0) Values(No) = Var % Values(l)          
        END IF
        
        Var => Var % Next          
      END DO

      IF(CalculateFlux) THEN
        l = NodeIndexes(node)        
        Values(No+1:No+3) = PointFluxes(SavedIndex(l),1:3)
      END IF
      
      DO i=1,NoResults
        WRITE(10,'(ES20.11E3)',ADVANCE='NO') Values(i)
      END DO
      WRITE(10,*)
      
    END DO

  END DO

  IF(CalculateFlux) THEN
    DEALLOCATE(PointFluxes)
  END IF

  !---------------------------------------------------------------------------
  ! Save data in the intersections of line segments defined by two coordinates
  ! and element faces, or save any of the principal axis.
  !---------------------------------------------------------------------------
  IF(NoLines > 0  .OR. ANY(SaveAxis(1:DIM)) ) THEN

    IF(.NOT. SubroutineVisited) THEN 
      CALL FindMeshEdges( Mesh, .FALSE.)
    END IF

    SavedIndex = 0

    IF(DIM == 2 .OR. IntersectEdge) THEN
      NoFaces = Mesh % NumberOfEdges
    ELSE 
      NoFaces = Mesh % NumberOfFaces
    END IF

    DO Line = 1,NoLines + NoAxis

      IF(Line <= NoLines) THEN
        LineNodes % x(1:2) = PointCoordinates(2*Line-1:2*Line,1) 
        LineNodes % y(1:2) = PointCoordinates(2*Line-1:2*Line,2) 
        IF(DIM == 3) LineNodes % z(1:2) = PointCoordinates(2*Line-1:2*Line,3) 
      ELSE 
        IF(.NOT. SaveAxis(Line-NoLines)) CYCLE
        ! Define the lines for principal axis
        IF(Line-NoLines == 1) THEN
          LineNodes % x(1) = MINVAL(Mesh % Nodes % x)
          LineNodes % x(2) = MAXVAL(Mesh % Nodes % x)
          LineNodes % y(1:2) = 0.0d0
          LineNodes % z(1:2) = 0.0d0
        ELSE IF(Line-NoLines == 2) THEN
          LineNodes % x(1:2) = 0.0d0
          LineNodes % y(1) = MINVAL(Mesh % Nodes % y)
          LineNodes % y(2) = MAXVAL(Mesh % Nodes % y)
          LineNodes % z(1:2) = 0.0d0
        ELSE          
          LineNodes % x(1:2) = 0.0d0
          LineNodes % y(1:2) = 0.0d0
          LineNodes % z(1) = MINVAL(Mesh % Nodes % z)
          LineNodes % z(2) = MAXVAL(Mesh % Nodes % z)
        END IF
      END IF


      DO t = 1,NoFaces
        
        IF(DIM == 2 .OR. IntersectEdge) THEN
          CurrentElement => Mesh % Edges(t)
        ELSE 
          CurrentElement => Mesh % Faces(t)
        END IF

        n = CurrentElement % TYPE % NumberOfNodes
        NodeIndexes => CurrentElement % NodeIndexes
        
        ElementNodes % x(1:n) = Mesh % Nodes % x(NodeIndexes)
        ElementNodes % y(1:n) = Mesh % Nodes % y(NodeIndexes)
        IF(DIM == 3) THEN
          ElementNodes % z(1:n) = Mesh % Nodes % z(NodeIndexes)
        ELSE
          ElementNodes % z(1:n) = 0.0d0
        END IF

        CALL GlobalToLocalCoords(CurrentElement,ElementNodes,n,LineNodes, &
            Inside,Basis,i)

        IF(.NOT. Inside) CYCLE

        ! print *,'i','basis',Basis(1:n),'node',NodeIndexes(i)

        ! When the line goes through a node it might be saved several times 
        ! without this checking
        IF(1.0d0-MAXVAL(Basis(1:n)) < 1.0d-3) THEN
          IF(SavedIndex(NodeIndexes(i)) == Line) CYCLE
          SavedIndex(NodeIndexes(i)) = Line 
        END IF

        SavedNodes = SavedNodes + 1
        
        IF(TransientSimulation) WRITE(10,'(I4)',ADVANCE='NO') Solver % DoneTime
        WRITE(10,'(I3,I3,I7)',ADVANCE='NO') TimesVisited,maxboundary+Line,NodeIndexes(i)
      
        Var => Model % Variables
        No = 0
        Values = 0.0d0
        
        DO WHILE( ASSOCIATED( Var ) )
          
          IF ( .NOT. Var % Output .OR. SIZE(Var % Values) == 1 .OR. &
              (Var % DOFs /= 1 .AND. .NOT. ASSOCIATED(Var % EigenVectors)) ) THEN
            Var => Var % Next        
            CYCLE
          END IF

          IF (ASSOCIATED (Var % EigenVectors)) THEN
            NoEigenValues = SIZE(Var % EigenValues) 
            DO j=1,NoEigenValues
              DO i=1,Var % DOFs
                DO k=1,n
                  l = NodeIndexes(k)
                  IF ( ASSOCIATED(Var % Perm) ) l = Var % Perm(l)
                  IF(l > 0) THEN 
                    Values(No+(j-1)*Var%Dofs+i) = Values(No+(j-1)*Var%Dofs+i) + &
                        Basis(k) * (Var % EigenVectors(j,Var%Dofs*(l-1)+i))
                  END IF
                END DO
              END DO
            END DO

            No = No + Var % Dofs * NoEigenValues
          ELSE 

            No = No + 1
            DO k=1,n
              l = NodeIndexes(k)
              IF ( ASSOCIATED(Var % Perm) ) l = Var % Perm(l)
              IF(l > 0) Values(No) = Values(No) + Basis(k) * (Var % Values(l))
            END DO

          END IF

          Var => Var % Next          
        END DO

        IF ( CalculateFlux ) Values(No+1:No+3) = 0.0
   
        DO i=1,NoResults
          WRITE(10,'(ES20.11E3)',ADVANCE='NO') Values(i)
        END DO
        WRITE(10,*)
        
      END DO

    END DO 

  END IF

  CLOSE(10)


  ! Finally save the names of the variables to help to identify the 
  ! columns in the result matrix.
  IF(.NOT. SubroutineVisited) THEN

    ALLOCATE( ValueNames(NoResults) )

    No = 0
    Var => Model % Variables
    DO WHILE( ASSOCIATED( Var ) )    

      IF ( .NOT. Var % Output .OR. SIZE(Var % Values) == 1 .OR. &
          (Var % DOFs /= 1 .AND. .NOT. ASSOCIATED(Var % EigenVectors)) ) THEN
        Var => Var % Next        
        CYCLE
      END IF

      IF (ASSOCIATED (Var % EigenVectors)) THEN
        NoEigenValues = SIZE(Var % EigenValues) 
        DO j=1,NoEigenValues
          DO i=1,Var % DOFs
            IF(i==1) THEN
              WRITE(ValueNames(No+(j-1)*Var%Dofs+i),'(A,I2,A,A,I2,A,2ES20.11E3)') &
                  "Eigen",j," ",TRIM(Var%Name),i,"   EigenValue = ",Var % EigenValues(j)
            ELSE 
              WRITE(ValueNames(No+(j-1)*Var%Dofs+i),'(A,I2,A,A,I2)') &
                  "Eigen",j," ",TRIM(Var%Name),i
            END IF
          END DO
        END DO
        No = No + Var % Dofs * NoEigenValues
      ELSE 
        No = No + 1
        ValueNames(No) = TRIM(Var % Name)
      END IF

      Var => Var % Next      
    END DO
    
    IF ( CalculateFlux ) THEN
      ValueNames(No+1) = 'Flux 1'
      ValueNames(No+2) = 'Flux 2'
      ValueNames(No+3) = 'Flux normal'      
    END IF
    
    SideNamesFile = TRIM(SideFile) // '.' // TRIM("names")
    OPEN (10, FILE=SideNamesFile)
    WRITE(10,'(A,A)') 'Variables in file: ',TRIM(SideFile)
    WRITE(10,'(I7,A)') SavedNodes,' nodes for each step'
    IF(SavedNodes > 0) THEN
      j = 0
      IF(TransientSimulation) THEN
        WRITE(10,'(I3,": ",A)') 1,'Time step'
        j = 1
      END IF
      WRITE(10,'(I3,": ",A)') 1+j,'Iteration step'
      WRITE(10,'(I3,": ",A)') 2+j,'Boundary condition'
      WRITE(10,'(I3,": ",A)') 3+j,'Node index'
      DO i=1,NoResults
        WRITE(10,'(I3,": ",A)') i+3+j,TRIM(ValueNames(i))
      END DO
    END IF
    CLOSE(10)
    DEALLOCATE( ValueNames )
  END IF

  SubroutineVisited = .TRUE.

CONTAINS


  SUBROUTINE GlobalToLocalCoords(Element,Plane,n,Line, &
      Inside,Weights,maxind)
! This subroutine tests whether the line segment goes through the current
! face of the element. If true the weights and index to the closest node 
! are returned. 

    TYPE(Nodes_t) :: Plane, Line
    TYPE(Element_t), POINTER   :: Element
    INTEGER :: n, maxind
    REAL (KIND=dp) :: Weights(:)
    LOGICAL :: Inside

    REAL (KIND=dp) :: A(3,3),A0(3,3),B(3),C(3),Eps,Eps2,detA,absA,ds
    INTEGER :: split, i, corners, visited=0
    REAL(KIND=dp) :: Basis(2*n),dBasisdx(2*n,3),ddBasisddx(n,3,3)
    REAL(KIND=dp) :: SqrtElementMetric,U,V,W=0.0d0

    SAVE visited
    visited = visited + 1

    Inside = .FALSE.
    corners = MIN(n,4)

    Eps = 1.0d-6
    Eps2 = SQRT(TINY(Eps2))    

    ! In 2D the intersection is between two lines
    IF(DIM == 2) THEN
      A(1,1) = Line % x(2) - Line % x(1)
      A(2,1) = Line % y(2) - Line % y(1)
      A(1,2) = Plane % x(1) - Plane % x(2)
      A(2,2) = Plane % y(1) - Plane % y(2)
      A0 = A

      detA = A(1,1)*A(2,2)-A(1,2)*A(2,1)
      absA = SUM(ABS(A(1,1:2))) * SUM(ABS(A(2,1:2)))

      IF(ABS(detA) <= eps * absA + Eps2) RETURN
      
      B(1) = Plane % x(1) - Line % x(1) 
      B(2) = Plane % y(1) - Line % y(1) 

      CALL InvertMatrix( A,2 )
      C(1:2) = MATMUL(A(1:2,1:2),B(1:2))

      IF(ANY(C(1:2) < 0.0) .OR. ANY(C(1:2) > 1.0d0)) RETURN

      Inside = .TRUE.
      u = -1.0d0 + 2.0d0 * C(2)
    END IF


    IF(DIM == 3 .AND. IntersectCoordinate /= 0) THEN
      IF(IntersectCoordinate == 1) THEN
        A(1,1) = Line % y(2) - Line % y(1)
        A(2,1) = Line % z(2) - Line % z(1)
        A(1,2) = Plane % y(1) - Plane % y(2)
        A(2,2) = Plane % z(1) - Plane % z(2)
      ELSE IF(IntersectCoordinate == 2) THEN
        A(1,1) = Line % x(2) - Line % x(1)
        A(2,1) = Line % z(2) - Line % z(1)
        A(1,2) = Plane % x(1) - Plane % x(2)
        A(2,2) = Plane % z(1) - Plane % z(2)
      ELSE IF(IntersectCoordinate == 3) THEN
        A(1,1) = Line % x(2) - Line % x(1)
        A(2,1) = Line % y(2) - Line % y(1)
        A(1,2) = Plane % x(1) - Plane % x(2)
        A(2,2) = Plane % y(1) - Plane % y(2)
      ELSE
        PRINT *,'Intersect',IntersectCoordinate
        CALL Fatal('GlobalToLocalCoords','Impossible value for parameter IntersectCoordinate')
      END IF

      A0 = A
      
      detA = A(1,1)*A(2,2)-A(1,2)*A(2,1)
      absA = SUM(ABS(A(1,1:2))) * SUM(ABS(A(2,1:2)))

      IF(ABS(detA) <= eps * absA + Eps2) RETURN
     
      B(1) = Plane % x(1) - Line % x(1) 
      B(2) = Plane % y(1) - Line % y(1) 

      CALL InvertMatrix( A,2 )
      C(1:2) = MATMUL(A(1:2,1:2),B(1:2))

!      PRINT *,'C',C(1:2)
!      PRINT *,'xp=',Plane % x(1) + C(2) * (Plane % x(2) - Plane % x(1)) 
!      PRINT *,'xl=',Line % x(1) + C(1) * (Line % x(2) - Line % x(1)) 
!      PRINT *,'yp=',Plane % y(1) + C(2) * (Plane % y(2) - Plane % y(1)) 
!      PRINT *,'yl=',Line % y(1) + C(1) * (Line % y(2) - Line % y(1)) 

      IF(ANY(C(1:2) < 0.0) .OR. ANY(C(1:2) > 1.0d0)) RETURN

      IF(IntersectCoordinate == 1) THEN
        ds = Line % x(1) + C(1)* (Line % x(2) - Line % x(1))  &
            - Plane % x(1) - C(2) * (Plane % x(1) - Plane % x(2))
      ELSE IF(IntersectCoordinate == 2) THEN
        ds = Line % y(1) + C(1)* (Line % y(2) - Line % y(1))  &
            - Plane % y(1) - C(2) * (Plane % y(1) - Plane % y(2))
      ELSE 
        ds = Line % z(1) + C(1)* (Line % z(2) - Line % z(1))  &
            - Plane % z(1) - C(2) * (Plane % z(1) - Plane % z(2))      
      END IF

      IF(ABS(ds) > IntersectEpsilon) RETURN

      Inside = .TRUE.
      u = -1.0d0 + 2.0d0 * C(2)
    END IF   

    
    ! In 3D rectangular faces are treated as two triangles
    IF(DIM == 3 .AND. IntersectCoordinate == 0) THEN

      DO split=0,corners-3
         
        A(1,1) = Line % x(2) - Line % x(1)
        A(2,1) = Line % y(2) - Line % y(1)
        A(3,1) = Line % z(2) - Line % z(1)

        IF(split == 0) THEN
          A(1,2) = Plane % x(1) - Plane % x(2)
          A(2,2) = Plane % y(1) - Plane % y(2)
          A(3,2) = Plane % z(1) - Plane % z(2)
        ELSE 
          A(1,2) = Plane % x(1) - Plane % x(4)
          A(2,2) = Plane % y(1) - Plane % y(4)
          A(3,2) = Plane % z(1) - Plane % z(4)
        END IF

        A(1,3) = Plane % x(1) - Plane % x(3)
        A(2,3) = Plane % y(1) - Plane % y(3)
        A(3,3) = Plane % z(1) - Plane % z(3)
        
        ! Check for linearly dependent vectors
        detA = A(1,1)*(A(2,2)*A(3,3)-A(2,3)*A(3,2)) &
             - A(1,2)*(A(2,1)*A(3,3)-A(2,3)*A(3,1)) &
             + A(1,3)*(A(2,1)*A(3,2)-A(2,2)*A(3,1))
        absA = SUM(ABS(A(1,1:3))) * SUM(ABS(A(2,1:3))) * SUM(ABS(A(3,1:3))) 

        IF(ABS(detA) <= eps * absA + Eps2) CYCLE
!        print *,'detA',detA

        B(1) = Plane % x(1) - Line % x(1)
        B(2) = Plane % y(1) - Line % y(1)
        B(3) = Plane % z(1) - Line % z(1)
        
        CALL InvertMatrix( A,3 )
        C(1:3) = MATMUL( A(1:3,1:3),B(1:3) )
        
        IF( ANY(C(1:3) < 0.0) .OR. ANY(C(1:3) > 1.0d0) ) CYCLE
        IF(C(2)+C(3) > 1.0d0) CYCLE

        Inside = .TRUE. 

        ! Relate the point of intersection to local coordinates
        IF(corners < 4) THEN
          u = C(2)
          v = C(3)
        ELSE IF(corners == 4 .AND. split == 0) THEN
          u = 2*(C(2)+C(3))-1
          v = 2*C(3)-1
        ELSE 
          ! For the 2nd split of the rectangle the local coordinates switched
          v = 2*(C(2)+C(3))-1
          u = 2*C(3)-1        
        END IF

        IF(Inside) EXIT
        
      END DO
    END IF

    IF(.NOT. Inside) RETURN

    stat = ElementInfo( Element, Plane, U, V, W, SqrtElementMetric, &
        Basis, dBasisdx, ddBasisddx, .FALSE., .FALSE. )

    IF(MAXVAL(Basis(1:n)-1.0) > eps .OR. MINVAL(Basis(1:n)) < -eps) THEN
      Inside = .FALSE.
    END IF
        
    Weights(1:n) = Basis(1:n)
    MaxInd = 1
    DO i=2,n
      IF(Weights(MaxInd) < Weights(i)) MaxInd = i
    END DO

  END SUBROUTINE GlobalToLocalCoords
  

   
  SUBROUTINE BoundaryFlux( Model, Node, VarName, CoeffName, f1, f2, fn, weight) 
    USE Types
    USE Lists
    USE ElementDescription
    
    TYPE(Model_t) :: Model
    INTEGER :: dimno,i,j,n,node
    CHARACTER(LEN=MAX_NAME_LEN) :: VarName, CoeffName
    REAL(KIND=dp) :: f1, f2, fn, weight
    
    TYPE(Variable_t), POINTER :: Tvar
    TYPE(Element_t), POINTER :: Parent, Element, OldCurrentElement
    TYPE(Nodes_t) :: Nodes
    TYPE(ValueList_t), POINTER :: Material
    REAL(KIND=dp) :: r,u,v,w,ub, &
        Basis(MAX_NODES),dBasisdx(MAX_NODES,3),ddBasisddx(1,1,1),DetJ, Normal(3)
    REAL(KIND=dp), TARGET :: x(MAX_NODES),y(MAX_NODES),z(MAX_NODES)
    LOGICAL :: stat, Permutated
    INTEGER :: body_id, k
    REAL(KIND=dp) :: Conductivity(MAX_NODES)
    REAL(KIND=DP), POINTER :: Pwrk(:,:,:)
    REAL(KIND=DP) :: CoeffTensor(3,3,Model % MaxElementNodes), Flow(3)

!-----------------------------------------------------------------------
!   Note that normal flux is calculated on the nodal points only
!   using a single boundary element. The direction of the normal
!   may be different on the nodal point when calculated using 
!   a neighboring boundary element.
!   Thus normal flow calculation is useful only when the boundary 
!   is relatively smooth. Also quadratic elements are recommended.
!   ( added by Antti )
!-----------------------------------------------------------------------

    Tvar => VariableGet( Model % Variables, TRIM(VarName) )
    Permutated = ASSOCIATED(Tvar % Perm)
    
    Element => Model % CurrentElement
    
    IF ( FluxBody > 0 ) THEN
      IF ( Element % BoundaryInfo % LBody == FluxBody ) THEN
        Parent => Element % BoundaryInfo % Left
      ELSEIF ( Element % BoundaryInfo % RBody == FluxBody ) THEN
        Parent => Element % BoundaryInfo % Right
      ELSE
        WRITE( MessageL, * ) 'No such flux integrate body on bc ', &
            Element % BoundaryInfo % Constraint
        CALL Fatal( 'SaveLine', MessageL )
      END IF
    ELSE        
      Parent => Element % BoundaryInfo % Left
      stat = ASSOCIATED( Parent )

      IF(Permutated) THEN
        IF(stat) stat = ALL(TVar % Perm(Parent % NodeIndexes) > 0)
        
        IF ( .NOT. stat ) THEN
          Parent => ELement % BoundaryInfo % Right
          
          stat = ASSOCIATED( Parent )
          IF(stat) stat = ALL(TVar % Perm(Parent % NodeIndexes) > 0)
        END IF
      END IF
      IF ( .NOT. stat )  CALL Fatal( 'SaveLine',&
          'No solution available for specified boundary' )
    END IF
    
    OldCurrentElement => Element
    Model % CurrentElement => Parent

    n = Parent % TYPE % NumberOfNodes
    
    Nodes % x => x
    Nodes % y => y
    Nodes % z => z
    Nodes % x(1:n) = Model % Nodes % x(Parent % NodeIndexes)
    Nodes % y(1:n) = Model % Nodes % y(Parent % NodeIndexes)
    Nodes % z(1:n) = Model % Nodes % z(Parent % NodeIndexes)
    
    DO j=1,n
      IF ( node == Parent % NodeIndexes(j) ) EXIT
    END DO

    IF ( node /= Parent % NodeIndexes(j) ) THEN
      CALL Warn('SaveLine','Side node not in parent element!')
    END IF
    
    CALL GlobalToLocal( u, v ,w , x(j), y(j), z(j), Parent, Nodes )

    stat = ElementInfo( Parent, Nodes, u, v, w, detJ, &
        Basis, dBasisdx, ddBasisddx, .FALSE., .FALSE. )
    weight = detJ
    
    ! Compute the normal of the surface for the normal flux
    DO j = 1, Element % TYPE % NumberOfNodes
      IF ( node == Element % NodeIndexes(j) ) EXIT
    END DO

    IF ( j == 1 ) THEN
      ub = -1.0d0
    ELSEIF ( j == 2 ) THEN
      ub = 1.0d0
    ELSE
      ub = 0.0d0
    END IF

    Normal = Normalvector( Element, ElementNodes, ub, 0.0d0, .TRUE. )

    body_id = Parent % Bodyid
    k = ListGetInteger( Model % Bodies(body_id) % Values,'Material', &
            minv=1, maxv=Model % NumberOFMaterials )
    Material => Model % Materials(k) % Values


    CALL ListGetRealArray( Material, TRIM(CoeffName), Pwrk, n, &
        Parent % NodeIndexes, GotIt )

    CoeffTensor = 0.0d0
    IF(GotIt) THEN
      IF ( SIZE(Pwrk,1) == 1 ) THEN
        DO i=1,3
          CoeffTensor( i,i,1:n ) = Pwrk( 1,1,1:n )
        END DO
      ELSE IF ( SIZE(Pwrk,2) == 1 ) THEN
        DO i=1,MIN(3,SIZE(Pwrk,1))
          CoeffTensor(i,i,1:n) = Pwrk(i,1,1:n)
        END DO
      ELSE
        DO i=1,MIN(3,SIZE(Pwrk,1))
          DO j=1,MIN(3,SIZE(Pwrk,2))
            CoeffTensor( i,j,1:n ) = Pwrk(i,j,1:n)
          END DO
        END DO
      END IF
    END IF
    
    Flow = 0.0d0
    DO j = 1, DIM
      DO k = 1, DIM
        IF(Permutated) THEN
          Flow(j) = Flow(j) + SUM( CoeffTensor(j,k,1:n) * Basis(1:n) ) * &
              SUM( dBasisdx(1:n,k) * TVar % Values(TVar % Perm(Parent % NodeIndexes(1:n))) )
        ELSE
          Flow(j) = Flow(j) + SUM( CoeffTensor(j,k,1:n) * Basis(1:n) ) * &
              SUM( dBasisdx(1:n,k) * TVar % Values(Parent % NodeIndexes(1:n)) ) 
        END IF
      END DO
    END DO

    f1 = Flow(1)
    f2 = Flow(2)
    fn = SUM(Normal(1:DIM) * Flow(1:DIM))

    Model % CurrentElement => OldCurrentElement

  END SUBROUTINE BoundaryFlux

!------------------------------------------------------------------------------
END SUBROUTINE SaveLine
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
! Additional routine for saving material parameters. 
! Written by Thomas Zwinger 
!------------------------------------------------------------------------------

SUBROUTINE SaveMaterials( Model,Solver,dt,TransientSimulation )
  !DEC$ATTRIBUTES DLLEXPORT :: SaveMaterial
  USE Types
  USE Lists
  USE Integration
  USE ElementDescription
  USE SolverUtils

  IMPLICIT NONE
!------------------------------------------------------------------------------
  TYPE(Solver_t), TARGET :: Solver
  TYPE(Model_t) :: Model
  REAL(KIND=dp) :: dt
  LOGICAL :: TransientSimulation
!------------------------------------------------------------------------------
! Local variables
!------------------------------------------------------------------------------
  TYPE(Solver_t), POINTER :: PointerToSolver
  TYPE(Mesh_t), POINTER :: Mesh
  TYPE(Element_t),POINTER :: CurrentElement
  TYPE(ValueList_t), POINTER :: Material
  INTEGER :: NoParams, DIM, ParamNo, istat, LocalNodes, body_id, material_id,&
       n, j, i, elementNumber
  INTEGER, POINTER :: Permutation(:),NodeIndexes(:)
  REAL(KIND=dp), ALLOCATABLE, TARGET :: Param(:,:)
  REAL(KIND=dp), POINTER :: PParam(:)
  CHARACTER(LEN=MAX_NAME_LEN) ::  ParamName(100), Name
  LOGICAL :: SubroutineVisited=.FALSE.,FirstTime=.TRUE., MovingMesh, GotCoeff, &
       GotIt, GotOper, GotVar, ExactCoordinates, ParamsExist

  CHARACTER(LEN=MAX_NAME_LEN) :: MessageL

  SAVE SubroutineVisited, DIM, LocalNodes, ParamName, Param, Permutation, NoParams

  !-----------------------------------
  ! get pointers to Solver information
  !-----------------------------------
  PointerToSolver => Solver

  IF ( .NOT. ASSOCIATED( PointerToSolver ) ) THEN
    CALL FATAL('SaveMaterials', ' No Solver Pointer associated')
  END IF

  !----------------------------------------
  ! Do these things for the first time only
  !----------------------------------------
  IF(.NOT.SubroutineVisited) THEN
     DIM = CoordinateSystemDimension()
     LocalNodes = Model % NumberOfNodes
     ALLOCATE(Permutation(LocalNodes))
     DO i=1,LocalNodes
       Permutation(i) = i
     END DO
     ! Find out how many variables should we saved
     NoParams = 0
     GotVar = .TRUE.
     ParamsExist = .FALSE.

     DO WHILE(GotVar)  
       NoParams = NoParams + 1
       IF(NoParams < 10) THEN
         WRITE (Name,'(A,I2)') 'Parameter',NoParams
       ELSE
         WRITE (Name,'(A,I3)') 'Parameter',NoParams    
       END IF
       ParamName(NoParams) = ListGetString( Solver % Values, TRIM(Name), GotVar )
       IF(GotVar) THEN
         WRITE(Message,'(A,A,A)') TRIM(Name),': ', ParamName(NoParams)
         CALL INFO('SaveMaterials',Message,Level=3)
       END IF
     END DO
     NoParams = NoParams-1

     ! --------------------------------------------
     ! Allocate space for new variables to be added
     ! --------------------------------------------
     IF(NoParams > 0) ParamsExist = .TRUE.
     IF (ParamsExist) THEN 
       ALLOCATE(Param( NoParams, LocalNodes ), &
           STAT=istat )
       IF (istat /= 0) THEN 
         CALL FATAL('SaveMaterials', 'Allocation Error')
       ELSE
         CALL INFO('SaveMaterials', 'Allocation done', Level=3)
         Param(1:NoParams,1:LocalNodes) = 0.0D00
       END IF
     END IF
     SubroutineVisited = .TRUE.

     !------------------
     ! Add new Variables
     ! -----------------
     IF (ParamsExist) THEN
       DO ParamNo = 1, NoParams
         PParam => Param(ParamNo,:)
         CALL VariableAdd( Solver % Mesh % Variables, Solver % Mesh, PointerToSolver, &
             TRIM(ParamName(ParamNo)), 1, PParam, Permutation)           
       END DO
     ELSE
       CALL WARN( 'SaveMaterials', 'No valid parameters found. Nothing will be written')
     END IF
  END IF

  !-----------------------------------
  ! Loop all active elements of solver
  !------------------------------------------------------
  DO elementNumber=1,Solver % Mesh % NumberOfBulkElements

     !--------------------------------
     ! get some information on element
     !--------------------------------
     CurrentElement => Solver % Mesh % Elements(elementNumber)
     Model % CurrentElement => CurrentElement
     body_id = CurrentElement % BodyId
     material_id = ListGetInteger( Model % Bodies(body_id) % Values, 'Material' )
     Material => Model % Materials(material_id) % Values
     IF (.NOT. ASSOCIATED(Material)) THEN
        WRITE( MessageL,'(a,i,a,i,a)')&
             'No Material for material-id ', material_id, ' for body-id ', body_id, &
             'associated'
        CALL FATAL('SaveMaterials', MessageL)
     END IF     
     n = CurrentElement % TYPE % NumberOfNodes
     NodeIndexes => CurrentElement % NodeIndexes

     !-----------------------------------
     ! loop all parameters to be exported
     !-------------------------------------
     DO i=1,NoParams
       
       Param(i,NodeIndexes(1:n)) = ListGetReal(Material, TRIM(ParamName(i)), n, NodeIndexes, GotIt)

       IF (.NOT. GotIt) THEN ! post a warning if parameter not found in material section
         WRITE( MessageL,'(A,I3,A,A,A,I3)') 'No entry for Parameter ', i, ': ',&
             TRIM(ParamName(i)),' found in material no. ', material_id
         CALL WARN('SaveMaterials', MessageL)
       END IF
     END DO! end loop over parameters
     !-------------------------------------
   END DO! end loop over all active elements of solver  

END SUBROUTINE SaveMaterials

!------------------------------------------------------------------------------
! Additional routine for saving boundary values 
! Written by Thomas Zwinger 
!------------------------------------------------------------------------------
SUBROUTINE SaveBoundaryValues( Model,Solver,dt,TransientSimulation )
  !DEC$ATTRIBUTES DLLEXPORT :: SaveMaterial
  USE Types
  USE Lists
  USE Integration
  USE ElementDescription
  USE SolverUtils
  USE DefUtils

  IMPLICIT NONE
!------------------------------------------------------------------------------
  TYPE(Solver_t), TARGET :: Solver
  TYPE(Model_t) :: Model
  REAL(KIND=dp) :: dt
  LOGICAL :: TransientSimulation
!------------------------------------------------------------------------------
! Local variables
!------------------------------------------------------------------------------
  TYPE(Solver_t), POINTER :: PointerToSolver
  TYPE(Mesh_t), POINTER :: Mesh
  TYPE(Element_t),POINTER :: BoundaryElement
  TYPE(ValueList_t), POINTER :: BC
  INTEGER :: NoParams, DIM, ParamNo, istat, LocalNodes, bc_id,&
       n, j, i, t
  INTEGER, POINTER :: Permutation(:),NodeIndexes(:)
  REAL(KIND=dp), ALLOCATABLE, TARGET :: Param(:,:)
  REAL(KIND=dp), POINTER :: PParam(:)
  CHARACTER(LEN=MAX_NAME_LEN) ::  ParamName(100), Name
  LOGICAL :: SubroutineVisited=.FALSE.,FirstTime=.TRUE., MovingMesh, GotCoeff, &
       GotIt, GotOper, GotVar, ExactCoordinates, ParamsExist

  CHARACTER(LEN=MAX_NAME_LEN) :: MessageL

  SAVE SubroutineVisited, DIM, LocalNodes, ParamName, Param, Permutation, NoParams

  !-----------------------------------
  ! get pointers to Solver information
  !-----------------------------------
  PointerToSolver => Solver

  IF ( .NOT. ASSOCIATED( PointerToSolver ) ) THEN
    CALL FATAL('SaveBoundaryValues', ' No Solver Pointer associated')
  END IF

  !----------------------------------------
  ! Do these things for the first time only
  !----------------------------------------
  IF(.NOT.SubroutineVisited) THEN
     DIM = CoordinateSystemDimension()
     LocalNodes = Model % NumberOfNodes
     ALLOCATE(Permutation(LocalNodes))
     DO i=1,LocalNodes
       Permutation(i) = i
     END DO
     ! Find out how many variables should we saved
     NoParams = 0
     GotVar = .TRUE.
     ParamsExist = .FALSE.

     DO WHILE(GotVar)  
       NoParams = NoParams + 1
       IF(NoParams < 10) THEN
         WRITE (Name,'(A,I2)') 'Parameter',NoParams
       ELSE
         WRITE (Name,'(A,I3)') 'Parameter',NoParams    
       END IF
       ParamName(NoParams) = ListGetString( Solver % Values, TRIM(Name), GotVar )
       IF(GotVar) THEN
         WRITE(Message,'(A,A,A)') TRIM(Name),': ', ParamName(NoParams)
         CALL INFO('SaveBoundaryValues',Message,Level=3)
       END IF
     END DO
     NoParams = NoParams-1

     ! --------------------------------------------
     ! Allocate space for new variables to be added
     ! --------------------------------------------
     IF(NoParams > 0) ParamsExist = .TRUE.
     IF (ParamsExist) THEN 
       ALLOCATE(Param( NoParams, LocalNodes ), &
           STAT=istat )
       IF (istat /= 0) THEN 
         CALL FATAL('SaveBoundaryValues', 'Allocation Error')
       ELSE
         CALL INFO('SaveBoundaryValues', 'Allocation done', Level=3)
         Param(1:NoParams,1:LocalNodes) = 0.0D00
       END IF
     END IF
     SubroutineVisited = .TRUE.

     !------------------
     ! Add new Variables
     ! -----------------
     IF (ParamsExist) THEN
       DO ParamNo = 1, NoParams
         PParam => Param(ParamNo,:)
         CALL VariableAdd( Solver % Mesh % Variables, Solver % Mesh, PointerToSolver, &
             TRIM(ParamName(ParamNo)), 1, PParam, Permutation)           
       END DO
     ELSE
       CALL WARN( 'SaveBoundaryValues', 'No valid parameters found. Nothing will be written')
     END IF
  END IF

  !-----------------------------------
  ! set all values to zero
  !-----------------------------------
  DO i = 1, NoParams
     Param(i,1:LocalNodes) = 0.0d00
  END DO

  !-----------------------------------
  ! Loop all active elements of solver
  !------------------------------------------------------
  DO t=1,Solver % Mesh % NumberOfBoundaryElements

     !--------------------------------
     ! get some information on element
     !--------------------------------
     BoundaryElement => GetBoundaryElement(t)
     Model % CurrentElement => BoundaryElement
     NodeIndexes => BoundaryElement % NodeIndexes
     n = GetElementNOFNodes(BoundaryElement)
!              IF ( GetElementFamily() == 1 ) CYCLE
     BC => GetBC()
     bc_id = GetBCId( BoundaryElement )
     IF ( .NOT.ASSOCIATED( BC ) ) CYCLE
    
     !-----------------------------------
     ! loop all parameters to be exported
     !-------------------------------------
     DO i=1,NoParams
       
        Param(i,NodeIndexes(1:n)) = ListGetReal(BC, TRIM(ParamName(i)), n, NodeIndexes, GotIt)
        IF (.NOT.GotIt) THEN
           WRITE(MessageL,'(a,a,a,i3,a,i10)') 'Boundary property ',TRIM(ParamName(i)),&
                ' not found on boundary no. ',bc_id,' for element no. ', t
           CALL INFO('SaveBoundaryValues', MessageL, Level=4)
           Param(i,NodeIndexes(1:n)) = 0.0D00
        END IF
     END DO! end loop over parameters
     !-------------------------------------
  END DO! end loop over all boundary element
  
END SUBROUTINE SaveBoundaryValues
