!/******************************************************************************
! *
! *       ELMER, A Computational Fluid Dynamics Program.
! *
! *       Copyright 1st April 1995 - , CSC - Scientific Computing Ltd.
! *                                    Finland.
! *
! *       All rights reserved. No part of this program may be used,
! *       reproduced or transmitted in any form or by any means
! *       without the written permission of CSC.
! *
! *****************************************************************************/
!
! *****************************************************************************
! *
! *             Module Author: Peter R�back
! *
! *                   Address: CSC - Scenter for Scientific Computing
! *                            Tekniikantie 15a D
! *                            02101 Espoo, Finland
! *                            Tel. +358 0 457 2080
! *                    E-Mail: Peter.Raback@csc.fi
! *
! *                      Date: 04.06.2000
! *
! *               Modified by: Peter R�back
! *
! *      Date of modification: 31.5.2003
! *
! ****************************************************************************/


!------------------------------------------------------------------------------
SUBROUTINE StatElecReduced( Model,Solver,dt,TransientSimulation )
!DEC$ATTRIBUTES DLLEXPORT :: StatElecReduced
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Solve the Poisson equation for the electric potential and compute the 
!  electric field, flux, energy and capacitance
!  Applicable only to the 1D case.
!
!  ARGUMENTS:
!
!  TYPE(Model_t) :: Model,  
!     INPUT: All model information (mesh, materials, BCs, etc...)
!
!  TYPE(Solver_t) :: Solver
!     INPUT: Linear equation solver options
!
!  DOUBLE PRECISION :: dt,
!     INPUT: Timestep size for time dependent simulations
!
!  LOGICAL :: TransientSimulation
!     INPUT: Steady state or transient simulation
!
!******************************************************************************

  USE Types
  USE Lists
  USE Integration
  USE ElementDescription
  USE Differentials
  USE SolverUtils
  USE ElementUtils
  USE MEMUtilities
  USE DefUtils
  
  IMPLICIT NONE
!------------------------------------------------------------------------------
 
  TYPE(Model_t) :: Model
  TYPE(Solver_t), TARGET:: Solver
  REAL (KIND=DP) :: dt
  LOGICAL :: TransientSimulation
  
!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
  TYPE(Matrix_t),POINTER  :: StiffMatrix
  TYPE(Variable_t), POINTER :: AnyVar
  TYPE(Nodes_t)   :: ElementNodes
  TYPE(Element_t),POINTER :: CurrentElement, Parent
  TYPE(Solver_t), POINTER :: PSolver 
  TYPE(ValueList_t), POINTER :: Material

  INTEGER, PARAMETER :: NoPots = 2
  INTEGER :: i,j,k,mat_id,mat_idold,n,m,t,istat,LocalNodes,pos, GotElasticSpring, &
      NoPositions, NoAmplitudes, DIM, LumpingDegree, PotentialNo, CurrentDim, &
      NoElements, tag, ElemDim, ElemCorners, AplacElstatMode, Visited=0, MaxDim
  INTEGER, POINTER :: NodeIndexes(:), ForcePerm(:)
  
  LOGICAL :: AllocationsDone = .FALSE., gotIt, PullIn, BiasOn, &
      ApertureExists, Transient, FixedAperture, &
      ScanPosition, LayerExists=.FALSE., &
      HoleCorrection, ComputeSpring, ComputeEnergy, ComputeField, &
      TwoPotentialsExist, FileAppend, SymmetricCapacitor, &
      SideCorrection, ThicknessCorrection, stat, AplacExport=.FALSE., &
      StaticPressure, PositionOffset, LumpSix
  LOGICAL, ALLOCATABLE :: NodeComputed(:)

  REAL (KIND=DP) :: PermittivityOfVacuum, Zmax, Zmin, Zcritical, Zpos=0.0, &
      Zposold, ScanRangeMax, ScanRangeMin, ScanMaxAsymmetry, ScanLinear, &
      aa,bb,cc,dd,ee,at,st,CPUTime,s, Capacitance(NoPots), LumpedEnergy(NoPots), &
      LumpedSpring0, MaxPotential(NoPots), LumpedSpringDz, ElasticPos, &
      LumpedSpringDzDz, PullInVoltage, OldLumpedForce, ElasticSpring, &
      PullInScale=1.0, PullInScaleOld=1.0, PullInAccuracy, PullInRelative, Work, &
      OldMaxForce, ForceRatio, Alpha, Beta, Gamma, AplacData(10), &
      MaxAperture, MinAperture, OldLumpedForce0=0.0, ElasticPos0=0.0, &
      Volume0, Pressure0, dVolume, dPressure=0.0, dPrevPressure=0.0, Volume, &
      IntPressureForce, ExtPressureForce, PressureSpring, PrevPressureSpring, &
      Relax, ExtPressure, MaxAmplitude, PrevExtPressureForce=0.0d0

  REAL (KIND=DP), POINTER :: ForceVector(:), Field(:), Force(:), Spring(:), &
      Energy(:), Array(:,:), ElemWork(:), SideEnergy(:), SideSpring(:), SideForce(:), &
      ElemAmplitude(:,:), ElemAperture(:)
 
  REAL (KIND=DP), ALLOCATABLE ::  Permittivity(:), HoleSize(:), HoleFraction(:), &
      LayerPermittivity(:), Thickness(:), Density(:), &
      Width(:), LayerThickness(:), EffectiveAperture(:), &
      ElemEnergy(:), ElemForce(:), ElemSpring(:), ElemCharge(:), &
      PotentialDifference(:), LumpedForce(:,:), LumpedCharge(:,:), &
      LumpedSpring(:,:,:), LumpingFactors(:,:)

  CHARACTER(LEN=MAX_NAME_LEN) :: EquationName, Filename, FilenameNames, &
      HoleType, String1
  CHARACTER :: Too
  
  ! These variables are for efficient manipulation of local scalats data
  INTEGER, PARAMETER :: MaxNoValues = 100
  INTEGER :: NoValues
  REAL (KIND=dp) ::  Values(MaxNoValues) 
  CHARACTER(LEN=MAX_NAME_LEN) :: ValueNames(MaxNoValues), ValueUnits(MaxNoValues)
  LOGICAL :: ValueSaveLocal(MaxNoValues),ValueSaveRes(MaxNoValues)
  CHARACTER(LEN=MAX_NAME_LEN) :: VersionID = "$Id: MEMStatElecReduced.f90,v 1.13 2005/04/27 12:23:16 raback Exp $"

  
  SAVE ElementNodes, AllocationsDone, Field, Force, Energy, Spring, &
      Permittivity, ElemAmplitude, ElemAperture, &
      Visited, ElemWork, LayerPermittivity, &
      Thickness, Density, LayerThickness, HoleSize, HoleFraction, NoAmplitudes, &
      LumpedForce, LumpedSpring, EffectiveAperture, ElemCharge, &
      ElemEnergy, ElemForce, ElemSpring, LumpedCharge, &
      PotentialDifference, ComputeEnergy, ComputeSpring, ComputeField, &
      LumpingFactors, NodeComputed, Width, ElasticPos0, OldLumpedForce0, &
      SideEnergy, SideSpring, SideForce, PullInScale, PullInScaleOld, Zpos, Zcritical, &
      Volume0, dPressure, dPrevPressure, PressureSpring, PrevExtPressureForce


  CALL Info('MEMStatElecReduced','----------------------------------',Level=5)
  CALL Info('MEMStatElecReduced','1-Dimensional electrostatic solver',Level=5)
  CALL Info('MEMStatElecReduced','----------------------------------',Level=5)

!------------------------------------------------------------------------------
!    Check if version number output is requested
!------------------------------------------------------------------------------
  IF ( .NOT. AllocationsDone ) THEN
    IF ( ListGetLogical( GetSimulation(), 'Output Version Numbers', GotIt ) ) THEN
      CALL Info( 'MEMStatElecReduced', 'MEMStatElecReduced version:', Level = 0 ) 
      CALL Info( 'MEMStatElecReduced', VersionID, Level = 0 ) 
      CALL Info( 'MEMStatElecReduced', ' ', Level = 0 ) 
    END IF
  END IF

!------------------------------------------------------------------------------
!    Get variables needed for solution
!------------------------------------------------------------------------------
  Force     => Solver % Variable % Values
  ForcePerm => Solver % Variable % Perm
  LocalNodes = Model % NumberOfNodes
  StiffMatrix => Solver % Matrix
  ForceVector => StiffMatrix % RHS

  Transient = .NOT. ListGetLogical( Solver % Values,'Steady State',GotIt)
  IF(.NOT. GotIt) Transient = TransientSimulation
  
!---------------------------------------------------------------------------------------
! These are two special cases where the displacement is found within the iteration.
! Pull-in analysis finds a new amplitude so that the amplitude is defined by the 
! electrostatics alone, and BiasOn finds a new amplitude so that the electric 
! forces are the same as those of a linear spring.
!---------------------------------------------------------------------------------------

  LumpSix = ListGetLogical( Model % Simulation,'Lump Six',GotIt)
  
  String1 = ListGetString( Solver % Values, 'Analysis Type',GotIt)
  BiasOn = .FALSE.
  PullIn = .FALSE.
  ScanPosition = .FALSE.
  NoPositions = 0



  SELECT CASE(String1)

    CASE ('pull in')
    PullIn = .TRUE.
    PullInAccuracy = ListGetConstReal( &
        Solver % Values, 'Nonlinear System Convergence Tolerance',gotIt,0.0d0)
    IF(.NOT. GotIt) PullInAccuracy = 1.0d-4
    NoPositions = ListGetInteger( &
        Solver % Values, 'Nonlinear System MAX Iterations',gotIt,minv=1)
    IF(.NOT. GotIt) NoPositions = 20
    
    CASE ('bias')
    BiasOn = .TRUE.
    PullInAccuracy = ListGetConstReal( &
        Solver % Values, 'Nonlinear System Convergence Tolerance',gotIt,0.0d0)
    IF(.NOT. GotIt) PullInAccuracy = 1.0d-4      
    NoPositions = ListGetInteger( &
        Solver % Values, 'Nonlinear System MAX Iterations',gotIt,minv=1)
    IF(.NOT. GotIt) NoPositions = 20
     
    CASE ('scan')
    ScanPosition = .TRUE.
    NoPositions = ListGetInteger( Solver % Values, 'Scan Points',gotIt,minv=2)
    IF(.NOT. gotIt) NoPositions = 20    
    ScanRangeMin = ListGetConstReal( Solver % Values, 'Scan Range Min',gotIt )
    IF(.NOT. gotIt) ScanRangeMin = -0.5d0        
    ScanRangeMax = ListGetConstReal( Solver % Values, 'Scan Range Max',gotIt )
    IF(.NOT. gotIt) ScanRangeMax = 0.5d0

    CASE ('none')      

  CASE DEFAULT 

    CALL Info('MEMStatElecReduced','Using default analysis type')

  END SELECT

  FixedAperture = BiasOn .OR. PullIn .OR. ScanPosition

  IF(FixedAperture) THEN
    Filename = ListGetString(Solver % Values,'Filename',GotIt )
    IF(.NOT. gotIt) Filename = 'elstat.dat'

    FilenameNames = TRIM(Filename) // '.' // TRIM("names")    
    CALL Info('StatElecReduced','Saving results to '//TRIM(Filename),Level=5)

    FileAppend = ListGetLogical(Solver % Values,'File Append',GotIt)
    IF(.NOT. GotIt) FileAppend = .TRUE.
  END IF

  MaxAmplitude = 0.0d0
  CALL ComputeAperture(Model, Solver, dt, Transient, FixedAperture, &
      ElemAperture, ElemAmplitude, .TRUE., ApertureExists, MaxAmplitude, &
      NoAmplitudes)
  IF(LumpSix) NoAmplitudes = 6


  !--------------------------------------------------------------------------
  ! Which types of corrections should be taken into account?
  !--------------------------------------------------------------------------
  HoleCorrection = ListGetLogical( Solver % Values, 'Hole Correction',gotIt )
  SideCorrection = ListGetLogical( Solver % Values, 'Side Correction',gotIt )
  ThicknessCorrection = ListGetLogical( Solver % Values, 'Thickness Correction',gotIt )


  EquationName = ListGetString( Solver % Values, 'Equation' )
  
  PermittivityOfVacuum = ListGetConstReal( Model % Constants, &
      'Permittivity Of Vacuum',gotIt )
  IF ( .NOT.gotIt ) PermittivityOfVacuum = 8.8542d-12

  DO k = 1, Model % NumberOfSolvers
    String1 = ListGetString( Model % Solvers(k) % Values, 'Equation',gotIt )
    AplacExport = ListGetLogical( Model % Solvers(k) % Values, 'Lumped Electrostatics',gotIt )
    IF(AplacExport) EXIT
  END DO

  LumpingDegree = ListGetInteger( Solver % Values,'Lumping Degree',GotIt)
  IF(.NOT. GotIt) LumpingDegree = 1
  IF(AplacExport) LumpingDegree = 3

  DIM = CoordinateSystemDimension()

  StaticPressure = ListGetLogical( Solver % Values, 'Static Pressure',GotIt)


!------------------------------------------------------------------------------
!    Allocate some permanent storage, this is done first time only
!------------------------------------------------------------------------------

  IF ( .NOT. AllocationsDone ) THEN

    N = Model % MaxElementNodes
    M = MAX(NoAmplitudes,1)

    ALLOCATE( ElementNodes % x(N),   &
        ElementNodes % y(N),   &
        ElementNodes % z(N),   &
        Permittivity(N),       &
        LayerPermittivity(N),       &
        Thickness(N),       &
        Density(N),       &
        LayerThickness(N),       &
        ElemCharge(N),       &
        ElemEnergy(N), &
        ElemForce(N), &
        ElemSpring(N), &
        Width(N), &
        EffectiveAperture(N), &
        ElemAmplitude(M,N),       &
        LumpedForce(NoPots,M), &
        LumpedCharge(NoPots,M), &
        LumpedSpring(NoPots,M,M), &
        PotentialDifference(N), &
        ElemAperture(N),       &
        ElemWork(N),       &
        HoleFraction(N),         &
        HoleSize(N),         &
        NodeComputed(Model%NumberOfNodes), &
        LumpingFactors(LumpingDegree+1,LumpingDegree+1), &
        STAT=istat )
    
    IF ( istat /= 0 ) THEN
      CALL FATAL('StatElecReduced','Memory allocation error')
    END IF

!------------------------------------------------------------------------------
!      Add electric field to the variable list
!------------------------------------------------------------------------------
    PSolver => Solver
    
    NULLIFY(AnyVar)
    AnyVar => VariableGet( Model % Variables, 'ElectricField' )
    IF(ASSOCIATED (AnyVar)) THEN
      ComputeField = .TRUE.
      Field => AnyVar % Values
    ELSE
      ComputeField = ListGetLogical(Solver % Values, 'Calculate Electric Field',gotIt )
      IF ( ComputeField ) THEN
        ALLOCATE( Field( Model%NumberOfNodes ), STAT=istat )
        IF ( istat /= 0 ) CALL Fatal( 'StatElecSolve', 'Memory allocation error.' )     
        CALL VariableAdd( Solver % Mesh % Variables, Solver % Mesh, &
            PSolver, 'ElectricField', 1, Field, ForcePerm)
      END IF
    END IF

    NULLIFY(AnyVar)
    AnyVar => VariableGet( Model % Variables, 'ElectricEnergy' )
    IF(ASSOCIATED (AnyVar)) THEN
      ComputeEnergy = .TRUE.
      Energy => AnyVar % Values
    ELSE
      ComputeEnergy = ListGetLogical(Solver % Values, 'Calculate Electric Energy',gotIt )
      IF ( ComputeEnergy ) THEN
        ALLOCATE( Energy( Model%NumberOfNodes ), STAT=istat )
        IF ( istat /= 0 ) CALL Fatal( 'StatElecSolve', 'Memory allocation error.' )     
        CALL VariableAdd( Solver % Mesh % Variables, Solver % Mesh, &
            PSolver, 'ElectricEnergy', 1, Energy, ForcePerm)
      END IF
    END IF
    
    NULLIFY(AnyVar)
    AnyVar => VariableGet( Model % Variables, 'ElectricSpring' )
    IF(ASSOCIATED (AnyVar)) THEN
      ComputeSpring = .TRUE.
      Spring => AnyVar % Values
    ELSE
      ComputeSpring = ListGetLogical(Solver % Values, 'Calculate Electric Spring',gotIt )
      IF ( ComputeSpring ) THEN
        ALLOCATE( Spring( Model%NumberOfNodes ), STAT=istat )
        IF ( istat /= 0 ) CALL Fatal( 'StatElecSolve', 'Memory allocation error.' )     
        CALL VariableAdd( Solver % Mesh % Variables, Solver % Mesh, &
            PSolver, 'ElectricSpring', 1, Spring, ForcePerm)
      END IF
    END IF
    
    IF(SideCorrection) THEN
      NULLIFY(AnyVar)
      AnyVar => VariableGet( Model % Variables, 'SideElectricForce' )
      IF(ASSOCIATED (AnyVar)) THEN
        SideForce => AnyVar % Values
      ELSE 
        ALLOCATE( SideForce( Model%NumberOfNodes ), STAT=istat )
        IF ( istat /= 0 ) CALL Fatal( 'StatElecSolve', 'Memory allocation error.' )     
        CALL VariableAdd( Solver % Mesh % Variables, Solver % Mesh, &
            PSolver, 'SideElectricForce', 1, SideForce, ForcePerm)
      END IF

      NULLIFY(AnyVar)
      AnyVar => VariableGet( Model % Variables, 'SideElectricEnergy' )
      IF(ASSOCIATED (AnyVar)) THEN
        SideEnergy => AnyVar % Values
      ELSE IF(ComputeEnergy) THEN
        ALLOCATE( SideEnergy( Model%NumberOfNodes ), STAT=istat )
        IF ( istat /= 0 ) CALL Fatal( 'StatElecSolve', 'Memory allocation error.' )     
        CALL VariableAdd( Solver % Mesh % Variables, Solver % Mesh, &
            PSolver, 'SideElectricEnergy', 1, SideEnergy, ForcePerm)
      END IF

      NULLIFY(AnyVar)
      AnyVar => VariableGet( Model % Variables, 'SideElectricSpring' )
      IF(ASSOCIATED (AnyVar)) THEN
        SideSpring => AnyVar % Values
      ELSE IF(ComputeSpring) THEN
        ALLOCATE( SideSpring( Model%NumberOfNodes ), STAT=istat )
        IF ( istat /= 0 ) CALL Fatal( 'StatElecSolve', 'Memory allocation error.' )     
        CALL VariableAdd( Solver % Mesh % Variables, Solver % Mesh, &
            PSolver, 'SideElectricSpring', 1, SideSpring, ForcePerm)
      END IF
    END IF

    AllocationsDone = .TRUE.

  END IF
!------------------------------------------------------------------------------
!    Do some additional initialization, and go for it
!------------------------------------------------------------------------------

  GotElasticSpring = 0
  OldMaxForce = MAXVAL(ABS(Force))


  ElasticSpring = ListGetConstReal( Model % Simulation,  &
      'res: Elastic Spring 1',GotIt )
  IF(GotIt) GotElasticSpring = 1

  IF(.NOT. GotIt) THEN
    PositionOffset = ListGetLogical(Solver % Values,'Position Offset',GotIt)
    IF(PositionOffset) THEN
      ElasticPos = ListGetConstReal( Model % Simulation,'res: Elastic Displacement')          
      IF(Visited == 0) THEN
        ElasticPos0 = ElasticPos
        OldLumpedForce0 = 0.0       
      ELSE IF(ABS(ElasticPos - ElasticPos0) > 1.0d-20) THEN
        ElasticSpring = (OldLumpedForce-OldLumpedForce0) / (ElasticPos-ElasticPos0)        
        GotElasticSpring = 2
      END IF
    ELSE IF(Visited > 0) THEN      
      ElasticPos = ListGetConstReal( Model % Simulation,'res: Elastic Displacement',GotIt)          
      IF(ABS(ElasticPos) > 1.0d-20) THEN
        ElasticSpring = OldLumpedForce / ElasticPos
        GotElasticSpring = 2
      END IF
    END IF
  END IF

  IF(PullIn .OR. BiasOn) THEN
    PullInScaleOld = PullInScale
  END IF


  Thickness = 0.0d0
  mat_idold = -1
  Zmax = -1.0d0
  Zmin = 1.0d0
  PressureSpring = 0.0d0
  IntPressureForce = 0.0d0
  ExtPressureForce = PrevExtPressureForce
  MaxAperture = -HUGE(MaxAperture)
  MinAperture = HUGE(MinAperture)


  DO pos=0,NoPositions

    IF(pos > 0 .OR. ((PullIn .OR. BiasOn) .AND. Visited > 0)) THEN
      IF((LumpedForce(1,1)+LumpedForce(2,1)) * (LumpedSpring(1,1,1)+LumpedSpring(2,1,1)) > 0) THEN
        Zpos = ABS(Zpos)
      ELSE
        Zpos = -ABS(Zpos)
      END IF
      ZposOld = Zpos


      IF(PullIn) THEN
        IF(GotElasticSpring > 0) THEN
          Zpos = Zpos/3.0d0 + (2.0/3.0)*ElasticPos0 + & 
              (2.0d0/3.0d0)*(LumpedForce(1,1)+LumpedForce(2,1)+ExtPressureForce)/ &
              (LumpedSpring(1,1,1)+LumpedSpring(2,1,1))
        ELSE 
          Zpos = Zpos/3.0d0 + &
              (2.0d0/3.0d0)*(LumpedForce(1,1)+LumpedForce(2,1))/ &
              (LumpedSpring(1,1,1)+LumpedSpring(2,1,1))
        END IF          
        PullInRelative = ABS(Zpos/Zcritical)
        IF(Visited == 0 .AND. pos == 1) THEN
          Zpos = SIGN(0.5*Zcritical,Zpos)
        END IF
      ELSE IF(BiasOn .AND. GotElasticSpring > 0) THEN
        PRINT *,'Zpos',Zpos,ElasticSpring,IntPressureForce,ExtPressureForce,LumpedForce(1,1)
        PRINT *,'Kp',PressureSpring

        Zpos = Zpos/3.0d0 + (2.0/3.0)*ElasticPos0 + &
            (2.0d0/3.0d0)*(LumpedForce(1,1)+LumpedForce(2,1)+ExtPressureForce) / &
            (ElasticSpring + PressureSpring)
      ELSE IF(ScanPosition) THEN
        ScanLinear = ScanRangeMin + &
            (ScanRangeMax-ScanRangeMin) * (pos-1.0d0)/ (NoPositions-1.0d0)
        Zpos = Zcritical * ScanLinear 
      END IF
    ELSE
      Zpos = 0.0d0
    END IF

    IF((PullIn .OR. BiasOn) .AND. (pos > 1)) THEN
      IF(PullInAccuracy*ABS(Zpos+Zposold) > 2.0d0*ABS(Zpos-Zposold)) EXIT 
    END IF

    Force = 0.0d0
    IF(ComputeField) Field = 0.0d0
    IF(ComputeEnergy) Energy = 0.0d0
    IF(ComputeSpring) Spring = 0.0d0
    TwoPotentialsExist = .FALSE.
    NodeComputed = .FALSE.

    LumpedEnergy = 0.0d0
    LumpedForce = 0.0d0
    LumpedCharge = 0.0d0
    LumpedSpring = 0.0d0
    LumpedSpringDz = 0.0d0
    LumpedSpringDzDz = 0.0d0
    LumpingFactors = 0.0d0
    MaxPotential = 0.0d0

    Alpha = 1.0d0
    Beta = 1.0d0
    Gamma = 1.0d0

    Volume = 0.0d0

!-----------------------------------------------------------------------------
! Check the maximum dimension of elements for this equation
!-----------------------------------------------------------------------------
    MaxDim = 0
    DO t=1,Solver % Mesh % NumberOfBulkElements + Solver % Mesh % NumberOfBoundaryElements
      
      CurrentElement => Solver % Mesh % Elements(t)
      ElemCorners = CurrentElement % TYPE % ElementCode / 100
      
      IF(ElemCorners > 4) THEN
        ElemDim = 3
      ELSE IF(ElemCorners >= 3) THEN
        ElemDim = 2
      ELSE
        ElemDim = ElemCorners - 1
      END IF
            
      IF(ElemDim <= MaxDim) CYCLE
      IF ( CheckElementEquation( Model, CurrentElement, EquationName ) ) THEN
        MaxDim = MAX(MaxDim, ElemDim)
      END IF
    END DO
    MaxDim = MIN(2, MaxDim)


!------------------------------------------------------------------------------
! There may be two different potentials in the system that will result
! to different lumped quantities. Solve the 1D equation for electric field and 
! energy density for both of them.
!------------------------------------------------------------------------------

    DO PotentialNo = 1,2

      CurrentDim = MaxDim

      ! Initialize the table showing the computed bulk and side nodes
100   NodeComputed = .FALSE.

      DO t=1,Solver % Mesh % NumberOfBulkElements + Solver % Mesh % NumberOfBoundaryElements

!------------------------------------------------------------------------------

        CurrentElement => Solver % Mesh % Elements(t)
        ElemCorners = CurrentElement % TYPE % ElementCode / 100

        IF(ElemCorners > 4) THEN
          ElemDim = 3
        ELSE IF(ElemCorners >= 3) THEN
          ElemDim = 2
        ELSE
          ElemDim = ElemCorners - 1
        END IF
          
        IF(ElemDim /= CurrentDim) CYCLE

        Model % CurrentElement => Solver % Mesh % Elements(t)

        IF(ElemDim == MaxDim) THEN
          IF ( .NOT. CheckElementEquation( Model, CurrentElement, EquationName ) ) CYCLE

          n = CurrentElement % TYPE % NumberOfNodes
          NodeIndexes => CurrentElement % NodeIndexes
          
          mat_id = ListGetInteger( Model % Bodies(CurrentElement % BodyId) % &
              Values, 'Material', minv=1,maxv=Model % NumberOFMaterials )
        ELSE 
          n = CurrentElement % TYPE % NumberOfNodes
          NodeIndexes => CurrentElement % NodeIndexes
          i = CurrentElement % BoundaryInfo % Constraint

          gotIt = .FALSE.
          DO k=1, Model % NumberOfBCs
            tag = Model % BCs(k) % Tag
            IF(tag /= i) CYCLE
            
            stat = ListGetLogical(Model % BCs(k) % Values,'Open Side',gotIt)
            IF(stat) EXIT
          END DO

          IF(.NOT. stat) CYCLE

          Parent => CurrentElement % BoundaryInfo % Left
          
          stat = ASSOCIATED( Parent )
          IF ( stat ) stat = stat .AND. ALL(ForcePerm(Parent % NodeIndexes) > 0)
          
          IF(.NOT. stat) THEN
            Parent => CurrentELement % BoundaryInfo % Right
            
            stat = ASSOCIATED( Parent )
            IF ( stat ) stat = stat .AND. ALL(ForcePerm(Parent % NodeIndexes) > 0)
            IF ( .NOT. stat )  CALL Fatal( 'StatElecReduced', &
                'No electrostatics available for specified boundary' )
          END IF
          
          Model % CurrentElement => Parent

          mat_id = ListGetInteger( Model % Bodies(Parent % BodyId) % Values, &
              'Material', minv=1, maxv=Model % NumberOFMaterials )
        END IF
!------------------------------------------------------------------------------

        Material => Model % Materials(mat_id) % Values

        ElementNodes % x(1:n) = Solver % Mesh % Nodes % x(NodeIndexes)
        ElementNodes % y(1:n) = Solver % Mesh % Nodes % y(NodeIndexes)
        ElementNodes % z(1:n) = Solver % Mesh % Nodes % z(NodeIndexes)

        IF(PotentialNo == 1) THEN
          PotentialDifference(1:n) = ListGetReal( Material, &
              'Potential Difference B',n,NodeIndexes,GotIt )
          IF(GotIt) TwoPotentialsExist = .TRUE.
          PotentialDifference(1:n) = ListGetReal( Material, &
              'Potential Difference',n,NodeIndexes,gotIt )
        ELSE
          PotentialDifference(1:n) = ListGetReal( Material, &
              'Potential Difference B',n,NodeIndexes,GotIt )
        END IF
          
        IF(.NOT. GotIt) CYCLE

        MaxPotential(PotentialNo) = &
            MAX(MaxPotential(PotentialNo),ABS(MAXVAL(PotentialDifference(1:n))))
        
        Permittivity(1:n) = ListGetReal( Model % Materials(mat_id) % Values, &
            'Permittivity',n,NodeIndexes,GotIt)
        IF(.NOT.GotIt) Permittivity = 1.0d0 
        Permittivity(1:n) = Permittivity(1:n) * PermittivityOfVacuum
        
        LayerThickness(1:n) = ListGetReal( Model % Materials(mat_id) % Values, &
            'Layer Thickness',n,NodeIndexes,LayerExists)
        
        IF(LayerExists) THEN
          LayerPermittivity(1:n) = ListGetReal( Model % Materials(mat_id) % Values, &
              'Layer Permittivity',n,NodeIndexes,GotIt)
          IF(.NOT.GotIt) LayerPermittivity = 1.0d0 
          LayerPermittivity(1:n) = LayerPermittivity(1:n) * PermittivityOfVacuum
        END IF
        
        IF(ElemDim == MaxDim .AND. HoleCorrection) THEN
          HoleType = ListGetString(Material,'Hole Type')
          HoleSize(1:n) = ListGetReal( Material, 'Hole Size', n, NodeIndexes)
          HoleFraction = ListGetReal( Model % Materials(mat_id) % Values, &
              'Hole Fraction',n,NodeIndexes)
        END IF


        IF( (ElemDim == MaxDim - 1)  .AND. SideCorrection) THEN
          SymmetricCapacitor = ListGetLogical( Model % BCs(k) % Values,&
              'Symmetric Side',gotIt)
          Width(1:n) = ListGetReal(Model % BCs(k) % Values,'Effective Width', &
              n, NodeIndexes)
          Thickness(1:n) = ListGetReal( Model % Materials(mat_id) % Values, &
              'Thickness',n,NodeIndexes,gotIt)
          IF(.NOT. GotIt) THEN
            Thickness(1:n) = ListGetReal(Model % BCs(k) % Values,'Thickness', &
                n, NodeIndexes, gotIt) 
          END IF
          IF(ThicknessCorrection .AND. (.NOT. gotIt)) THEN
            CALL Warn('StatElecReduced','Thickness correction requires thickness')
          END IF
        END IF

        IF(ApertureExists) THEN
          CALL ComputeAperture(Model, Solver, dt, Transient, FixedAperture, &
              ElemAperture, ElemAmplitude, .FALSE. )
        ELSE
          ElemAmplitude(1,1:n) = ListGetReal( Material,'Amplitude',n,NodeIndexes)
          ElemAperture(1:n) = ListGetReal(Material,'Aperture',n,NodeIndexes)
          MaxAmplitude = MAX(MaxAmplitude, MAXVAL(ABS(ElemAmplitude(1,1:n))))
        END IF

        IF(ElemDim == MaxDim) THEN
          IF(pos == 0) THEN
            MaxAperture = MAX(MaxAperture, MAXVAL(ElemAperture(1:n)))
            MinAperture = MIN(MinAperture, MINVAL(ElemAperture(1:n)))
            Zmax = MAX(Zmax, MAXVAL(ElemAmplitude(1,1:n)/ElemAperture(1:n)))
            Zmin = MIN(Zmin, MINVAL(ElemAmplitude(1,1:n)/ElemAperture(1:n)))
          END IF
        END IF

        IF(FixedAperture) THEN
          ElemAperture(1:n) = ElemAperture(1:n) + Zpos * ElemAmplitude(1,1:n) 
        END IF

        DO i=1,n
          j = ForcePerm( NodeIndexes(i) )
          
          ! Compute stuff assuming a thin dielectric layer. 
          IF(LayerExists) THEN
            IF(ElemAperture(i) > LayerThickness(i)) THEN
              EffectiveAperture(i) = (ElemAperture(i) - LayerThickness(i)) + &
                  LayerThickness(i)*Permittivity(i)/LayerPermittivity(i)
            ELSE 
              EffectiveAperture(i) = ElemAperture(i) * Permittivity(i) / LayerPermittivity(i)
            END IF
          ELSE
            EffectiveAperture(i) = ElemAperture(i) 
          END IF

          ! For each area element use plate capacitor approximation
          IF(ElemDim == MaxDim) THEN
            IF(HoleCorrection) THEN
              CALL ComputeHoleCorrection(HoleType, HoleSize(i), Thickness(i), &
                  HoleFraction(i), EffectiveAperture(i), Alpha, Beta, Gamma)
            END IF

            ElemForce(i) = -0.5d0 * Beta * (PotentialDifference(i) ** 2.0d0) * &
                Permittivity(i) /  EffectiveAperture(i)**2.0            
            ElemEnergy(i) = 0.5d0 * Alpha * (PotentialDifference(i) ** 2.0d0) * &
                Permittivity(i) / EffectiveAperture(i)            
            ElemCharge(i) = Beta * PotentialDifference(i) * &
                Permittivity(i) /  EffectiveAperture(i)**2.0            
            ElemSpring(i) = Gamma * (PotentialDifference(i) ** 2.0d0) * &
                Permittivity(i) /  EffectiveAperture(i)**3.0

            IF(.NOT. NodeComputed(j)) THEN
              NodeComputed(j) = .TRUE.
              IF(PotentialNo == 1) THEN
                Force(j) = ElemForce(i) 
                IF(ComputeField) Field(j) = - PotentialDifference(i) / EffectiveAperture(i)
                IF(ComputeEnergy) Energy(j) = ElemEnergy(i)
                IF(ComputeSpring) Spring(j) = ElemSpring(i)
              ELSE
                Force(j) = Force(j) + ElemForce(i) 
                IF(ComputeField) Field(j) = Field(j) - PotentialDifference(i) / EffectiveAperture(i)
                IF(ComputeEnergy) Energy(j) = Energy(j) + ElemEnergy(i)
                IF(ComputeSpring) Spring(j) = Spring(j) + ElemSpring(i)
              END IF
            END IF
          END IF

          ! For each side element use fringe field approximation
          IF(ElemDim == MaxDim - 1) THEN           
            CALL ComputeSideCorrection(EffectiveAperture(i), Width(i), Thickness(i), &
                SymmetricCapacitor, Alpha, Beta, Gamma)

            ElemForce(i) = -0.5d0 * Beta * (PotentialDifference(i) ** 2.0d0) * &
                Permittivity(i) /  EffectiveAperture(i)            
            ElemEnergy(i) = 0.5d0 * Alpha * (PotentialDifference(i) ** 2.0d0) * &
                Permittivity(i)             
            ElemCharge(i) = Beta * PotentialDifference(i) * &
                Permittivity(i) /  EffectiveAperture(i)            
            ElemSpring(i) = Gamma * (PotentialDifference(i) ** 2.0d0) * &
                Permittivity(i) /  EffectiveAperture(i)**2.0

            IF(.NOT. NodeComputed(j)) THEN
              NodeComputed(j) = .TRUE.
              IF(PotentialNo == 1) THEN
                SideForce(j) = ElemForce(i) 
                IF(ComputeEnergy) SideEnergy(j) = ElemEnergy(i)
                IF(ComputeSpring) SideSpring(j) = ElemSpring(i)
              ELSE
                SideForce(j) = SideForce(j) + ElemForce(i) 
                IF(ComputeEnergy) SideEnergy(j) = SideEnergy(j) + ElemEnergy(i)
                IF(ComputeSpring) SideSpring(j) = SideSpring(j) + ElemSpring(i)
              END IF
            END IF
          END IF

        END DO

        CALL LumpedIntegral(n, Model, ElementNodes, CurrentElement, &
            ElemEnergy, ElemForce, ElemSpring, ElemCharge, &
            EffectiveAperture, ElemAmplitude)

      END DO  ! Of Elements

      IF(SideCorrection .AND. CurrentDim == MaxDim) THEN
        CurrentDim = MaxDim - 1 
        GOTO 100
      END IF

!------------------------------------------------------------------------------
!    Compute the lumped quantities for the electrostatic problem
!------------------------------------------------------------------------------

      IF(ABS(MaxPotential(PotentialNo)) < 1.0d-20) THEN
        CALL Fatal('StatElecReduced','There is no non-zero potential present')
      END IF

      Capacitance(PotentialNo) = 2.0d0 * LumpedEnergy(PotentialNo) / &
          (MaxPotential(PotentialNo) ** 2.0d0)

      IF(.NOT. (LumpSix .OR. ApertureExists)) THEN        
        LumpedForce(PotentialNo,1)  = LumpedForce(PotentialNo,1) / MaxAmplitude
        LumpedCharge(PotentialNo,1)  = LumpedCharge(PotentialNo,1) / MaxAmplitude
        LumpedSpring(PotentialNo,1,1) = LumpedSpring(PotentialNo,1,1) / (MaxAmplitude ** 2.0d0)
      END IF

      IF(.NOT. TwoPotentialsExist) EXIT
     
    END DO! PotentialNo    


    IF (pos == 0 .AND. Visited == 0) THEN
      Volume0 = Volume
      LumpedSpring0 = LumpedSpring(1,1,1)+LumpedSpring(2,1,1)
      ScanMaxAsymmetry = 100.0

      IF(Zmin >  -Zmax / ScanMaxAsymmetry) THEN
        Zmin = -Zmax / ScanMaxAsymmetry 
      ELSE IF(Zmax < -Zmin / ScanMaxAsymmetry) THEN
        Zmax = -Zmin / ScanMaxAsymmetry
      END IF
      Zmax = MAX(Zmax,TINY(Zmax))
      Zmin = MIN(Zmin,-TINY(Zmin))      
      Zmax = 1.0/Zmax
      Zmin = 1.0/Zmin
      IF(Zmax < -Zmin) THEN
        Zcritical = Zmax
        IF(ScanRangeMax > -Zmin/Zmax) ScanRangeMax = -Zmin/Zmax - 0.01
      ELSE 
        Zcritical = Zmin
        IF(ScanRangeMax > -Zmax/Zmin) ScanRangeMax = -Zmax/Zmin - 0.01
      END IF
!    ELSE 
!      aa = Zpos / ((LumpedSpring0/(LumpedSpring(1,1,1)+LumpedSpring(2,1,1))) ** (1.0/3.0) - 1.0)
    END IF

    IF(StaticPressure) THEN
      Pressure0 = ListGetConstReal( Solver % Values,'Reference Pressure')      
      ExtPressure = ListGetConstReal(Solver % Values,'External Pressure',GotIt)

      dPressure = -Pressure0 * (Volume - Volume0) / Volume
      IntPressureForce = LumpingFactors(2,1) * dPressure
      PressureSpring = LumpingFactors(2,1)**2.0 * Pressure0 / Volume
      ExtPressureForce = -LumpingFactors(2,1) * ExtPressure
    END IF

    IF(PullIn .AND. (pos > 0 .OR. Visited > 0)) THEN
      Relax = ListGetConstReal(Solver % Values,'Relax Spring',GotIt)
      IF(.NOT. GotIt) Relax = 1.0d0
      IF(Visited > 0) PressureSpring = (1.0-Relax)*PrevPressureSpring + Relax*PressureSpring

      IF(GotElasticSpring > 0) THEN
        PullInScale = SQRT(ABS((ElasticSpring+PressureSpring)/(LumpedSpring(1,1,1)+LumpedSpring(2,1,1)))) 
      END IF

      Relax = ListGetConstReal(Solver % Values,'Relax Voltage',GotIt)
      IF(.NOT. GotIt) Relax = 1.0d0

      PullInScale = Relax * PullInScale + (1-Relax) * PullInScaleOld

      LumpedForce = PullInScale**2.0 * LumpedForce
      LumpedSpring = PullInScale**2.0 * LumpedSpring
      
      PullInVoltage = PullInScale * MaxPotential(1)
      
      LumpedCharge = PullInScale * LumpedCharge
      LumpedSpringDz = PullInScale**2.0 * LumpedSpringDz
      LumpedSpringDzDz = PullInScale**2.0 * LumpedSpringDzDz
      
      Force = PullInScale**2.0 * Force
      IF(ComputeField) Field = PullInScale * Field
      IF(ComputeEnergy) Energy = PullInScale**2.0 * Energy 
      IF(ComputeSpring) Spring = PullInScale**2.0 * Spring
    END IF

    !-------------------------------------------------------------------------
    ! The same info may be echoed, printed to external files and
    ! saved for later usage with a prefix 'res:'
    !-------------------------------------------------------------------------
    NoValues = 0
    IF(pos > 0) CALL AddToSaveList('Position',Zpos,'(m)',.TRUE.,.FALSE.)
    CALL AddToSaveList('Critical amplitude',Zcritical,'(m)',.FALSE.,.FALSE.)

!    IF(GotElasticSpring == 2) CALL AddToSaveList('Elastic Spring',ElasticSpring,'(N/m)',.TRUE.,.TRUE.)      

    IF(StaticPressure) THEN
      CALL AddToSaveList('Int Pressure',dPressure,'(Pa)')
      CALL AddToSaveList('Pressure Spring',PressureSpring,'(N)')
      CALL AddToSaveList('Int Pressure Force',IntPressureForce,'(N/m)')
      CALL AddToSaveList('Ext Pressure Force',ExtPressureForce,'(N/m)')
    END IF

    DO PotentialNo=1,2
      IF(PotentialNo == 1) THEN
        Too = ' '
      ELSE
        Too = ' B'
      END IF

      CALL AddToSaveList('Max Potential'//Too,MaxPotential(PotentialNo),'(V)',.FALSE.,.TRUE.)
      CALL AddToSaveList('Capacitance'//Too,Capacitance(PotentialNo),'(C/V)')
      CALL AddToSaveList('Electric energy'//Too,LumpedEnergy(PotentialNo),'(J)')
      
      DO i=1,NoAmplitudes
        WRITE(Message,'(A,I1)') 'Electric Force'//Too,i
        CALL AddToSaveList(Message,LumpedForce(PotentialNo,i),'(N)')

        IF(.NOT. LumpSix) THEN
          WRITE(Message,'(A,I1)') 'Electric Current Sensitivity'//Too,i
          CALL AddToSaveList(Message,LumpedCharge(PotentialNo,i),'(C/m)')

          DO j=1,i
            WRITE(Message,'(A,I1,I1)') 'Electric Spring'//Too,i,j
            CALL AddToSaveList( Message,LumpedSpring(PotentialNo,i,j),'(N/m)')
          END DO
        END IF
      END DO

      IF(.NOT. TwoPotentialsExist) EXIT
    END DO

    IF(TwoPotentialsExist) THEN
      IF(NoAmplitudes > 1) THEN
        IF(ABS(LumpedForce(2,1)) < ABS(LumpedForce(2,2))) THEN
          Work = LumpedForce(2,1) / LumpedForce(2,2)
        ELSE
          Work = LumpedForce(2,2) / LumpedForce(2,1)
        END IF
        CALL AddToSaveList('Relative coupling',Work,'')
      END IF
    END IF      

    CALL AddToSaveList('Minimum Fluid Aperture',MinAperture,'(m)')
    CALL AddToSaveList('Maximum Fluid Aperture',MaxAperture,'(m)')

    IF(.NOT. LumpSix) THEN
      IF(.NOT. ApertureExists) THEN
        LumpedSpringDz = LumpedSpringDz / MaxAmplitude ** 3.0d0
        LumpedSpringDzDz = LumpedSpringDzDz / MaxAmplitude ** 4.0d0
        CALL AddToSaveList('Electric Spring Dz',LumpedSpringDz,'(N/m^2)')
        CALL AddToSaveList('Electric Spring DzDz',LumpedSpringDzDz,'(N/m^3)')
      END IF
      
      IF(.FALSE.) THEN
        bb =  -3.0d0 * (LumpedSpring(1,1,1)+LumpedSpring(2,1,1)) / LumpedSpringDz
        cc = SQRT(12.0d0 * ABS(LumpedSpring(1,1,1)+LumpedSpring(2,1,1))) / LumpedSpringDzDz
        CALL AddToSaveList('Lumped Spring D1',bb,'(m)',.FALSE.,.FALSE.)
        CALL AddToSaveList('Lumped Spring D2',cc,'(m)',.FALSE.,.FALSE.)
      END IF
      
      DO j=0,LumpingDegree
        DO i=0,LumpingDegree
          IF(i==0 .AND. j==0) THEN
            CALL AddToSaveList('Charged area',LumpingFactors(1,1),'m^2',.FALSE.)
          ELSE IF(j==0) THEN
            !          LumpingFactors(i+1,1) = LumpingFactors(i+1,1)/LumpingFactors(1,1)
            WRITE(Message,'(A,I1)') 'Lumping factor U^',i
            CALL AddToSaveList(Message,LumpingFactors(i+1,1),'',.FALSE.)
          ELSE 
            !          LumpingFactors(i+1,j+1) = (Zcritical**j)*LumpingFactors(i+1,j+1)/LumpingFactors(1,1)
            WRITE(Message,'(A,I1,A,I1)') 'Lumping factor U^',i,'/D^',j
            CALL AddToSaveList(Message,LumpingFactors(i+1,j+1),'')
          END IF
        END DO
      END DO
    END IF

    IF(PullIn) THEN
      CALL AddToSaveList('Pull-In Scale',PullInScale,'')
      CALL AddToSaveList('Pull-In Voltage',PullInVoltage,'(V)')
      CALL AddToSaveList('Pull-In Relative Displacement',PullInRelative,'')
    END IF
   
    IF(pos <= 1) THEN
      IF(NoPositions > 0) THEN
        WRITE(Message,'(A,I3,A)') 'Values after ',pos,' steps' 
        CALL Info('StatElecReduced',Message,Level=5)
      END IF
      DO t=1,NoValues
        WRITE(Message,'(A,T35,ES15.5)') TRIM(ValueNames(t))//' '//TRIM(ValueUnits(t)),Values(t)
        CALL Info('StatElecReduced',Message,Level=5)
      END DO
    END IF
    
    IF(pos == 1) THEN
      IF(PotentialNo > 1 .OR. (Visited > 0 .AND. FileAppend)) THEN 
        OPEN (10, FILE=Filename,POSITION='APPEND')
      ELSE 
        OPEN (10,FILE=Filename)
      END IF
    END IF

    IF(pos >= 1) THEN
      DO t=1,NoValues 
        IF(ValueSaveLocal(t)) WRITE(10,'(ES15.5)',ADVANCE='NO') Values(t)
      END DO
      IF(FileAppend) THEN 
        WRITE(10,'(I5)') pos
      ELSE
        WRITE(10,'(A)') ' '
      END IF
    ENDIF

    IF(ScanPosition .AND. pos == 0 ) THEN
      DO t=1,NoValues 
        IF(ValueSaveRes(t)) CALL ListAddConstReal( Model % Simulation, &
            'res: '//TRIM(ValueNames(t)), Values(t) )
      END DO
    END IF
    
    IF(ScanPosition .AND. AplacExport) THEN
      IF(pos == 0) CALL MakeAplacModel()
      IF(pos == 1) CALL MakeAplacModel()
      IF(pos == NoPositions) CALL MakeAplacModel()
    END IF

  END DO

  OldLumpedForce = LumpedForce(1,1)+LumpedForce(2,1)

  
  IF(StaticPressure) THEN
    Relax = ListGetConstReal(Solver % Values,'Relax Pressure',GotIt)
    IF(.NOT. GotIt) Relax = 1.0d0      

    IF(.NOT. ComputeSpring) THEN
      Force = Force + Relax * dPressure + (1-Relax) * dPrevPressure - ExtPressure
    ELSE
      NodeComputed = .FALSE.

      DO t=1,Solver % NumberOfActiveElements
        
        CurrentElement => Solver % Mesh % Elements(Solver % ActiveElements(t))
        Model % CurrentElement => CurrentElement
        
        n = CurrentElement % TYPE % NumberOfNodes
        NodeIndexes => CurrentElement % NodeIndexes
        
        mat_id = ListGetInteger( Model % Bodies( CurrentElement % &
            Bodyid ) % Values, 'Material', minv=1, maxv=Model % NumberOfMaterials )      
        Material => Model % Materials(mat_id) % Values
        
        IF(ApertureExists) THEN
          CALL ComputeAperture(Model, Solver, dt, .FALSE., .FALSE., &
              ElemAperture, ElemAmplitude, .FALSE.)
        ELSE
          ElemAperture(1:n) = ListGetReal(Material,'Aperture',n,NodeIndexes)
          ElemAmplitude(1,1:n) = ListGetReal(Material,'Amplitude',n,NodeIndexes)
        END IF
      
        DO i=1,n
          j = ForcePerm(NodeIndexes(i))
          
          IF(.NOT. NodeComputed(j)) THEN
            NodeComputed(j) = .TRUE.

            k = ListGetInteger(Solver % Values,'Mode',GotIt)
            IF(.NOT. GotIt) k = 1

            IF(k == 1) THEN
              aa = dPressure / ElemAperture(i)
            ELSE IF(k == 2) THEN
              aa = -dPressure / ( Zpos * LumpingFactors(2,1) / LumpingFactors(1,1))
            ELSE IF(k == 3) THEN
              aa = dPressure / Zpos
            ELSE IF(k == 4) THEN
              aa = dPressure / (LumpingFactors(1,1) / LumpingFactors(1,2))
            ELSE IF(k == 5) THEN
              aa = dPressure / ABS(MaxAperture)
            ELSE IF(k == 6) THEN
              aa = dPressure / ABS(MinAperture)
            END IF

            Force(j) = Force(j) - ExtPressure + dPressure + &
                 aa * ElemAmplitude(1,i) * Zpos 
            Spring(j) = aa
          END IF
        END DO

      END DO
    END IF

    OldLumpedForce = OldLumpedForce + IntPressureForce + ExtPressureForce

    dPrevPressure = dPressure 
    PrevPressureSpring = PressureSpring
    PrevExtPressureForce = ExtPressureForce
  END IF


  IF(NoPositions > 0) THEN
    CLOSE(10)
    OPEN (10, FILE=FilenameNames)
    WRITE(10,'(A)') 'Position dependent variables in file '//TRIM(Filename) 
    i = 0
    DO t=1,NoValues
      IF(ValueSaveLocal(t)) THEN
        i = i+1
        WRITE(10,'(I2,T4,A)') i,TRIM(ValueNames(t))//' '//TRIM(ValueUnits(t))
      END IF
    END DO
    WRITE(10,'(A)') 'Other variables and constants'
    DO t=1,NoValues
      IF(.NOT. ValueSaveLocal(t)) THEN
        WRITE(10,'(A,T20,ES15.5)') TRIM(ValueNames(t)),Values(t)
      END IF
    END DO
    CLOSE(10)
  END IF

  IF(pos > 1) THEN
    WRITE(Message,'(A,I3,A)') 'Values after ',pos,' steps' 
    CALL Info('StatElecReduced',Message,Level=5)
    DO t=1,NoValues
      WRITE(Message,'(A,T35,ES15.5)') &
          TRIM(ValueNames(t))//' '//TRIM(ValueUnits(t)),Values(t)
      CALL Info('StatElecResuced',Message,Level=5)
    END DO
  END IF

  ! Add variabes that may be read by other solvers and 
  ! saved to result matrix. 
  IF(.NOT. ScanPosition) THEN 
    DO t=1,NoValues
      IF(ValueSaveRes(t)) CALL ListAddConstReal( Model % Simulation, &
          'res: '//TRIM(ValueNames(t)), Values(t) )
    END DO
  END IF

  IF(AplacExport) CALL MakeAplacModel()  

  Visited = Visited + 1


!------------------------------------------------------------------------------
 

CONTAINS

  SUBROUTINE MakeAplacModel()
    
    INTEGER :: i,j,n,phase
    REAL(KIND=dp), POINTER :: kp(:,:), km(:,:), k0(:,:), e0, f0(:), cc(:,:)
    REAL(KIND=dp) :: phi, p, a, q, preva, f
    LOGICAL :: AplacAllocated = .FALSE.

    SAVE kp, km, k0, f0, cc, AplacAllocated, phase, p
    
    IF(.NOT. AplacAllocated) THEN
      n = NoAmplitudes
      ALLOCATE(kp(n,n), km(n,n), k0(n,n), f0(n), e0, cc(n,5))
      AplacAllocated = .TRUE.
    END IF


    PotentialNo = 1

    IF(.NOT. ScanPosition .OR. pos == 0) THEN

      CALL ListAddInteger( Model % Simulation, 'mems: elstat mode', 1)
      CALL ListAddConstReal( Model % Simulation, 'mems: elstat area', LumpingFactors(1,1))
      CALL ListAddConstReal( Model % Simulation, 'mems: elstat aeff1', LumpingFactors(2,1))
      CALL ListAddConstReal( Model % Simulation, 'mems: elstat aeff2', LumpingFactors(3,1))
      CALL ListAddConstReal( Model % Simulation, 'mems: elstat deff3', &
          (LumpingFactors(3,1)/LumpingFactors(3,4))**(1.0d0/3.0) )
      CALL ListAddConstReal( Model % Simulation, 'mems: elstat displ', Zpos)
      IF(Thickness(1) > 1.0d-20) THEN        
        CALL ListAddConstReal( Model % Simulation, 'mems: elstat thick', Thickness(1))
      END IF
      CALL ListAddConstReal( Model % Simulation, 'mems: elstat voltage', MaxPotential(1))
      CALL ListAddConstReal( Model % Simulation, 'mems: elstat capa', Capacitance(1))

      DO i=1,NoAmplitudes
        WRITE(Message,'(A,I1)') 'mems: elstat charge ',i
        CALL ListAddConstReal( Model % Simulation, Message, LumpedCharge(1,i)) 
        WRITE(Message,'(A,I1)') 'mems: elstat force ',i
        CALL ListAddConstReal( Model % Simulation, Message, LumpedForce(1,i)) 
        DO j=1,NoAmplitudes
          WRITE(Message,'(A,I1,I1)') 'mems: elstat spring ',i,j
          CALL ListAddConstReal( Model % Simulation, Message, LumpedSpring(1,i,j)) 
        END DO
      END DO
    END IF

    IF(ScanPosition) THEN 
      IF(pos == 0) THEN
        phase = 1
        e0 = LumpedEnergy(PotentialNo)
        
        phi = MaxPotential(PotentialNo)
        IF(ABS(ScanRangeMax+ScanRangeMin) > 1.0d-4) THEN
          CALL Fatal('StatElecReduced','In fitting Aplac results Range should be symmetric')
        END IF
        p = (ScanRangeMax - ScanRangeMin) / 2.0d0
        DO i=1,NoAmplitudes
          f0(i) = LumpedForce(PotentialNo,i)
          DO j=1,NoAmplitudes
            k0(i,j) = LumpedSpring(PotentialNo,i,j)
          END DO
        END DO
      ELSE IF(pos == 1) THEN
        IF(phase /= 1) CALL Warn('StatElecReduced','Phase should be 1') 
        phase = 2
        DO i=1,NoAmplitudes
          DO j=1,NoAmplitudes
            km(i,j) = LumpedSpring(PotentialNo,i,j)
          END DO
        END DO
      ELSE IF(pos == NoPositions) THEN
        IF(phase /= 2) CALL Warn('StatElecReduced','Phase should be 2') 
        phase = 3
        DO i=1,NoAmplitudes
          DO j=1,NoAmplitudes
            kp(i,j) = LumpedSpring(PotentialNo,i,j)
          END DO
        END DO
      END IF
      
      IF(phase == 3) THEN
        DO i=1,NoAmplitudes
          q = (kp(i,i) + km(i,i)) / k0(i,i)
          preva = 0.0d0
          a = 1.0d0
          j = 0
          DO WHILE(ABS(a-preva) > 1.0d-6)
            j = j + 1
            preva = a
            a = 2.0d0 + LOG(q-(1.0+p)**(a-2.0)) / (LOG(1.0-p)) 
            IF(j > 20) THEN
              CALL Warn('StatElecReduced','Convergence for power a was not obtained')
              EXIT
            END IF
          END DO
          cc(i,1) = a
          
          cc(i,2) = (km(i,i) - (1.0+p)**(a-2.0)*k0(i,i)) / ((1-p)**(a-2.0) - (1+p)**(a-2.0))
          cc(i,2) = cc(i,2) * 2.0 * Zcritical**2.0 / a / (a-1.0) / phi**2.0
          
          cc(i,3) = (km(i,i) - (1.0-p)**(a-2.0)*k0(i,i)) / ((1+p)**(a-2.0) - (1-p)**(a-2.0))
          cc(i,3) = cc(i,3) * 2.0 * Zcritical**2.0 / a / (a-1.0) / phi**2.0
          
          cc(i,4) = f0(i) - (cc(i,2) - cc(i,3)) * phi**2.0 * cc(i,1) / Zcritical / 2.0d0
          cc(i,4) = cc(i,4) * 2.0 * Zcritical / phi**2.0
          
          cc(i,5) = 2.0*e0/phi**2.0 - cc(i,2) - cc(i,3) 
        END DO

        i = 1
        a = cc(i,2) + cc(i,3) + cc(i,5)
        cc(i,2:5) = cc(i,2:5) / a

        ! Using five evnly distributed test points Capacitance is fitted to model 
        ! C=C_0(b_0 + b_1 p + b_i (1+p)^a + b_d (1-p)^a), where (p=d/d_0) and
        ! a=C0, cc(i,5)=b_0, cc(i,4)=b_1, cc(i,3)=b_i, cc(i,2)=b_d, cc(i,1)=a

        CALL ListAddInteger( Model % Simulation, 'mems: elstat mode', 2)
        CALL ListAddConstReal( Model % Simulation, 'mems: elstat zcrit', Zcritical)
        CALL ListAddConstReal( Model % Simulation, 'mems: elstat aeff0', LumpingFactors(1,1))

        CALL ListAddConstReal( Model % Simulation, 'mems: elstat capa', a)
        CALL ListAddConstReal( Model % Simulation, 'mems: elstat c1', cc(i,1))      
        CALL ListAddConstReal( Model % Simulation, 'mems: elstat c2', cc(i,2))
        CALL ListAddConstReal( Model % Simulation, 'mems: elstat c3', cc(i,3))
        CALL ListAddConstReal( Model % Simulation, 'mems: elstat c4', cc(i,4))
        CALL ListAddConstReal( Model % Simulation, 'mems: elstat c5', cc(i,5))
    
        phase = 0
      END IF

    END IF

  END SUBROUTINE MakeAplacModel

!------------------------------------------------------------------------------

  SUBROUTINE AddToSaveList(Name, Value, Unit, savelocal, saveres)

    INTEGER :: n
    CHARACTER(LEN=*) :: Name, Unit
    REAL(KIND=dp) :: Value
    LOGICAL, OPTIONAL :: savelocal,saveres

    n = NoValues
    n = n + 1
    IF(n > MaxNoValues) THEN
      CALL WARN('StatElecReduced','Too little space for the scalars')
      RETURN
    END IF

    Values(n) = Value
    ValueNames(n) = TRIM(Name)
    ValueUnits(n) = TRIM(Unit)
    IF(PRESENT(savelocal)) THEN
      ValueSaveLocal(n) = savelocal
    ELSE 
      ValueSaveLocal(n) = .TRUE.
    END IF
    IF(PRESENT(saveres)) THEN
      ValueSaveRes(n) = saveres
    ELSE 
      ValueSaveRes(n) = .TRUE.
    END IF

    NoValues = n

  END SUBROUTINE AddToSaveList



!------------------------------------------------------------------------------
   SUBROUTINE LumpedIntegral(n, Model, ElementNodes, CurrentElement,  &
       Energy, Force, Spring, Charge, Aperture, Amplitude)

 !------------------------------------------------------------------------------
     INTEGER :: n
     TYPE(Model_t) :: Model
     TYPE(Nodes_t) :: ElementNodes
     TYPE(Element_t), POINTER :: CurrentElement
     REAL(KIND=dp) :: Energy(:), Force(:), Spring(:), &
         Aperture(:), Amplitude(:,:), Charge(:)

!------------------------------------------------------------------------------
     
     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff
     REAL(KIND=dp), DIMENSION(:), POINTER :: &
         U_Integ,V_Integ,W_Integ,S_Integ
     REAL(KIND=dp) :: s,ug,vg,wg
     REAL(KIND=dp) :: ddBasisddx(Model % MaxElementNodes,3,3), Normal(3), Moment(3), Axis(3)
     REAL(KIND=dp) :: Basis(Model % MaxElementNodes)
     REAL(KIND=dp) :: dBasisdx(Model % MaxElementNodes,3),SqrtElementMetric
     REAL(KIND=dp) :: Amplitudei, Amplitudej
     INTEGER :: N_Integ, t, tg, ii, jj, i,j,k,l
     LOGICAL :: stat

!------------------------------------------------------------------------------
!    Gauss integration stuff
!------------------------------------------------------------------------------
     IntegStuff = GaussPoints( CurrentElement )
     U_Integ => IntegStuff % u
     V_Integ => IntegStuff % v
     W_Integ => IntegStuff % w
     S_Integ => IntegStuff % s
     N_Integ =  IntegStuff % n

!------------------------------------------------------------------------------
! Loop over Gauss integration points
!------------------------------------------------------------------------------
     
     DO tg=1,N_Integ

       ug = U_Integ(tg)
       vg = V_Integ(tg)
       wg = W_Integ(tg)

!------------------------------------------------------------------------------
! Need SqrtElementMetric and Basis at the integration point
!------------------------------------------------------------------------------
       stat = ElementInfo( CurrentElement,ElementNodes,ug,vg,wg, &
           SqrtElementMetric,Basis,dBasisdx,ddBasisddx,.FALSE. )

       s = SqrtElementMetric * S_Integ(tg)
 
       IF ( CurrentCoordinateSystem() /= Cartesian ) THEN
         s = s * 2.0d0 * PI * SUM( ElementNodes % x(1:n) * Basis(1:n)) 
       END IF

       IF(ElemDim == 2) THEN
         Volume = Volume + s * SUM(Aperture(1:n) * Basis(1:n)) 
       END IF

       ! Calculate the function to be integrated at the Gauss point
       LumpedEnergy(PotentialNo) = LumpedEnergy(PotentialNo) + &
           s * SUM( Energy(1:n) * Basis(1:n) )

       IF(LumpSix) THEN
         Normal = Normalvector(CurrentElement, ElementNodes, ug, vg, .FALSE.)
         Axis(1) =  SUM( ElementNodes % x(1:n) * Basis(1:n))
         Axis(2) =  SUM( ElementNodes % y(1:n) * Basis(1:n))
         Axis(3) =  SUM( ElementNodes % z(1:n) * Basis(1:n))
         Moment = CrossProduct(Normal,Axis) 

         DO i = 1, 6
           IF(i < 4) THEN
             Amplitudei = ABS(Normal(i))
           ELSE
             Amplitudei = Moment(i-3)
           END IF           

           LumpedForce(PotentialNo,i) = LumpedForce(PotentialNo,i) + &
               s * Amplitudei * SUM( Force(1:n) * Basis(1:n) )
           LumpedCharge(PotentialNo,i) = LumpedCharge(PotentialNo,i) + &
               s * Amplitudei * SUM( Charge(1:n) * Basis(1:n) )           

           DO j = 1, 6
             IF(j < 4) THEN
               Amplitudej = ABS(Normal(j))
             ELSE
               Amplitudej = Moment(j-3)
             END IF
             LumpedSpring(PotentialNo,i,j) = LumpedSpring(PotentialNo,i,j) + &
                 s * Amplitudei * Amplitudej * SUM( Spring(1:n) * Basis(1:n) )             
           END DO
           
         END DO

       ELSE
         
         DO i=1,NoAmplitudes
           
           Amplitudei = SUM(Amplitude(i,1:n) * Basis(1:n))
           
           LumpedForce(PotentialNo,i) = LumpedForce(PotentialNo,i) + &
               s * Amplitudei * SUM( Force(1:n) * Basis(1:n) )
           LumpedCharge(PotentialNo,i) = LumpedCharge(PotentialNo,i) + &
               s * Amplitudei * SUM( Charge(1:n) * Basis(1:n) )
           
           DO j=1,NoAmplitudes
             Amplitudej = SUM(Amplitude(j,1:n) * Basis(1:n))
             LumpedSpring(PotentialNo,i,j) = LumpedSpring(PotentialNo,i,j) + &
                 s * Amplitudei * Amplitudej * SUM( Spring(1:n) * Basis(1:n) )
           END DO
           
           IF(ElemDim == 2) THEN
             LumpedSpringDz = LumpedSpringDz + s * &
                 (-3.0d0 * Amplitudei**3.0) * SUM(Spring(1:n) * Basis(1:n) / Aperture(1:n) )
             LumpedSpringDzDz = LumpedSpringDzDz + s * &
                 (-3.0d0 * Amplitudei**4.0) * SUM(Spring(1:n) * Basis(1:n) / Aperture(1:n)**2.0 )
           END IF
         END DO
         
         IF(ElemDim == 2 .AND. PotentialNo == 1) THEN
           DO k=0,LumpingDegree
             DO l=0,LumpingDegree
               IF(k==0 .AND. l==0) THEN
                 LumpingFactors(k+1,l+1) = LumpingFactors(k+1,l+1) + &
                     s * SUM(Basis(1:n)) 
               ELSE IF(k==0) THEN
                 LumpingFactors(k+1,l+1) = LumpingFactors(k+1,l+1) + &
                     s * SUM(Basis(1:n) / (Aperture(1:n)**l) )
               ELSE IF(l==0) THEN
                 LumpingFactors(k+1,l+1) = LumpingFactors(k+1,l+1) + &
                     s * SUM(Basis(1:n) * (Amplitude(1,1:n)**k) )
               ELSE
                 LumpingFactors(k+1,l+1) = LumpingFactors(k+1,l+1) + &
                     s * SUM(Basis(1:n) * (Amplitude(1,1:n)**k) / (Aperture(1:n)**l) )
               END IF
             END DO
           END DO
         END IF

       END IF

     END DO! of the Gauss integration points
       
!------------------------------------------------------------------------------
   END SUBROUTINE LumpedIntegral
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
 FUNCTION CrossProduct(Vector1,Vector2) RESULT(Vector)
   IMPLICIT NONE
   REAL(KIND=dp) :: Vector1(3),Vector2(3),Vector(3)

   Vector(1) = Vector1(2)*Vector2(3) - Vector1(3)*Vector2(2)
   Vector(2) = -Vector1(1)*Vector2(3) + Vector1(3)*Vector2(1)
   Vector(3) = Vector1(1)*Vector2(2)-Vector1(2)*Vector2(1)

 END FUNCTION CrossProduct
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   SUBROUTINE ComputeHoleCorrection(holemodel, r, b, p, d, alpha, beta, gamma)
     ! r=radius, b=hole length, d=aperture, p=hole fraction
     
     CHARACTER(LEN=*) :: holemodel
     REAL(KIND=dp) :: r,d,b,p,alpha,beta,gamma,a,da,dda,c1,c2,dom

     SELECT CASE(holemodel)

       CASE ('slot')
       c1 = 2.3198
       c2 = 0.2284 
 
       CASE ('round')
       c1 = 4.2523d0
       c2 = 0.4133d0
       
       CASE ('square')
       c1 = 3.8434 
       c2 = 0.3148

     CASE DEFAULT 
       alpha = 1.0
       beta = 1.0
       gamma = 1.0

       CALL WARN('ComputeHoleCorrection','Unknown hole type')       

       RETURN
     END SELECT
 
     dom = 1.0d0 + c1*(d/r) + c2* (d/r)**2.0
     a = 1.0 - p * 1.0d0/dom
     da = p * (c1+2.0*c2*(d/r)) / dom**2.0
     dda = p * 2.0 * (c2-2.0* c1**2.0-3.0*c1*c2*(d/r)-3.0* c2**2.0 * (d/r)**2.0) / dom**3.0     
      
     alpha = a
     beta = a - da*(d/r)
     gamma = a - da*(d/r) + 0.5d0*dda*((d/r)**2.0)
     
   END SUBROUTINE ComputeHoleCorrection
   
!------------------------------------------------------------------------------

   SUBROUTINE ComputeSideCorrection(h, a, t, symm, alpha, beta, gamma)
     ! h=aperture, a=width, t=thickness
     ! From APLAC documentation by Timo Veijola     
     ! The result is multiplied appropriately so that the units vanish

     LOGICAL :: symm
     REAL(KIND=dp) :: h, a, t, alpha, beta, gamma, csymm
     REAL(KIND=dp) :: ah, ahh, th, hh, f, fh, fhh, c1th, thc3, c2thc3
     REAL(KIND=dp), PARAMETER :: c1=2.158, c2=0.153, c3=0.231, c4=0.657

     a = a / 2.0d0

     IF(symm) THEN
       csymm = 1.0d0
     ELSE
       csymm = 2.0d0
     END IF

     h = csymm * h
     th = t/h
     hh = h*h

     IF(th < 1.0d-20) THEN
       alpha = (csymm / PI) * ( 1.0 + LOG(2*PI*a/h) )
       beta = csymm / PI 
       gamma = csymm / PI
     ELSE
       c2thc3 = c2+th**c3

       f = LOG(c3*th/c2thc3+1.0)
       fh = -c3**2.0 * c2thc3 / (h*c2thc3**2.0)

       a = c1*th/c2thc3
       ah = -(a/h)*(1-c3*(th**c3)/c2thc3)
       ahh = (ah-a/h)*ah/a - (a/h)*fh

       alpha = (csymm / PI) * ( 1.0 + LOG(2*PI*a/h) + c4*a)
       beta = csymm * (-h / PI) * (-1.0/h + c4*ah/(a+1) )
       gamma = csymm * (hh / PI) * (1/hh + c4*ahh/(a+1) - c4*(ah/(a+1))**2.0 )
     END IF

   END SUBROUTINE ComputeSideCorrection
!------------------------------------------------------------------------------

   
 END SUBROUTINE StatElecReduced
!------------------------------------------------------------------------------

