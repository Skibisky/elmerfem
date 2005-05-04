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
! * Module containing a solver for the general non-linear elasticity equations
! *
! ******************************************************************************
! *
! *                     Author:       Juha Ruokolainen
! *
! *                    Address: Center for Scientific Computing
! *                            Tietotie 6, P.O. Box 405
! *                              02101 Espoo, Finland
! *                              Tel. +358 0 457 2723
! *                            Telefax: +358 0 457 2302
! *                          EMail: Juha.Ruokolainen@csc.fi
! *
! *                       Date:        08 Jun 1997
! *
! *                Modified by:         Mikko Lyly
! * 
! *                    Address: CSC - Scientific Computing Ltd
! *                         Tekniikantie 15 a D, P.O. Box 405
! *                               02101 Espoo, Finland
! *                               Tel. +358 9 457 2053
! *                             Telefax: +358 9 457 2302
! *                             EMail: Mikko.Lyly@csc.fi
! *
! *       Date of modification:        27 Apr 2000
! *
! *****************************************************************************/

!------------------------------------------------------------------------------
   SUBROUTINE ElasticSolver( Model, Solver, dt, TransientSimulation )
  !DEC$ATTRIBUTES DLLEXPORT :: ElasticSolver
!------------------------------------------------------------------------------

    USE Adaptive
    USE DefUtils
    USE MaterialModels

    IMPLICIT NONE

!------------------------------------------------------------------------------
!******************************************************************************
!
!  Solve elasticity equations for one timestep
!
!  ARGUMENTS:
!
!  TYPE(Model_t) :: Model,  
!     INPUT: All model information (mesh,materials,BCs,etc...)
!
!  TYPE(Solver_t) :: Solver
!     INPUT: Linear equation solver options
!
!  REAL(KIND=dp) :: dt,
!     INPUT: Timestep size for time dependent simulations (NOTE: Not used
!            currently)
!
!******************************************************************************

     TYPE(Model_t)  :: Model
     TYPE(Solver_t), TARGET :: Solver

     LOGICAL ::  TransientSimulation
     REAL(KIND=dp) :: dt
!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
     TYPE(Matrix_t),POINTER :: StiffMatrix

     INTEGER :: i,j,k,l,m,n,t,iter,NDeg,k1,k2,STDOFs,LocalNodes,istat,AdjacentElement

     TYPE(Solver_t), POINTER :: PSolver

     TYPE(ValueList_t),POINTER :: Material
     TYPE(Nodes_t) :: ElementNodes,ParentNodes,FlowNodes
     TYPE(Element_t),POINTER :: CurrentElement, ParentElement, FlowElement

     REAL(KIND=dp) :: RelativeChange,UNorm,PrevUNorm,Gravity(3), &
         Tdiff,Normal(3),NewtonTol,NonlinearTol,s,TOL(1)

     INTEGER :: NewtonIter,NonlinearIter, FlowNOFNodes

     TYPE(Variable_t), POINTER :: StressSol, TempSol, FlowSol

     REAL(KIND=dp), POINTER :: Temperature(:),Pressure(:),Displacement(:), &
          Work(:,:),ForceVector(:),Velocity(:,:),FlowSolution(:),SaveValues(:)

     INTEGER,POINTER :: TempPerm(:),StressPerm(:),PressPerm(:),NodeIndexes(:), &
          FlowPerm(:),AdjacentNodes(:)

     INTEGER :: StressType
     LOGICAL :: GotForceBC,GotIt,NewtonLinearization = .FALSE.
     LOGICAL :: LinearModel = .FALSE., MeshDisplacementActive

     INTEGER :: body_id,bf_id,eq_id,CoordinateSystem
     LOGICAL :: PlaneStress
!
     LOGICAL :: AllocationsDone = .FALSE.

     CHARACTER(LEN=MAX_NAME_LEN) :: str, CompressibilityFlag
     LOGICAL :: CompressibilityDefined = .FALSE.

     REAL(KIND=dp),ALLOCATABLE:: LocalMassMatrix(:,:),LocalStiffMatrix(:,:),&
          LocalDampMatrix(:,:),LoadVector(:,:),Viscosity(:),LocalForce(:), &
          LocalTemperature(:),ElasticModulus(:),PoissonRatio(:), Density(:), &
          Damping(:), HeatExpansionCoeff(:,:,:),Alpha(:,:),Beta(:), &
          ReferenceTemperature(:),BoundaryDispl(:),LocalDisplacement(:,:)


     SAVE LocalMassMatrix,LocalStiffMatrix,LocalDampMatrix,LoadVector,Viscosity, &
       LocalForce,ElementNodes,ParentNodes,FlowNodes,Alpha,Beta, &
         LocalTemperature,AllocationsDone,ReferenceTemperature,BoundaryDispl, &
           ElasticModulus, PoissonRatio,Density,Damping,HeatExpansionCoeff, &
           LocalDisplacement, Velocity, Pressure
!------------------------------------------------------------------------------
     INTEGER :: NumberOfBoundaryNodes
     INTEGER, POINTER :: BoundaryReorder(:)

     REAL(KIND=dp) :: Bu,Bv,Bw,RM(3,3)
     REAL(KIND=dp), POINTER :: BoundaryNormals(:,:), &
         BoundaryTangent1(:,:), BoundaryTangent2(:,:)

     SAVE NumberOfBoundaryNodes,BoundaryReorder,BoundaryNormals, &
              BoundaryTangent1, BoundaryTangent2

     REAL(KIND=dp) :: at,at0,CPUTime,RealTime
     INTEGER :: TotalSteps,LoadStep, dim


     CHARACTER(LEN=MAX_NAME_LEN) :: EquationName
     CHARACTER(LEN=MAX_NAME_LEN) :: VersionID = "$Id: ElasticSolve.f90,v 1.48 2005/04/21 06:44:44 jpr Exp $"


     INTERFACE
        FUNCTION ElastBoundaryResidual( Model,Edge,Mesh,Quant,Perm, Gnorm ) RESULT(Indicator)
          USE Types
          TYPE(Element_t), POINTER :: Edge
          TYPE(Model_t) :: Model
          TYPE(Mesh_t), POINTER :: Mesh
          REAL(KIND=dp) :: Quant(:), Indicator(2), Gnorm
          INTEGER :: Perm(:)
        END FUNCTION ElastBoundaryResidual

        FUNCTION ElastEdgeResidual( Model,Edge,Mesh,Quant,Perm ) RESULT(Indicator)
          USE Types
          TYPE(Element_t), POINTER :: Edge
          TYPE(Model_t) :: Model
          TYPE(Mesh_t), POINTER :: Mesh
          REAL(KIND=dp) :: Quant(:), Indicator(2)
          INTEGER :: Perm(:)
        END FUNCTION ElastEdgeResidual

        FUNCTION ElastInsideResidual( Model,Element,Mesh,Quant,Perm, Fnorm ) RESULT(Indicator)
          USE Types
          TYPE(Element_t), POINTER :: Element
          TYPE(Model_t) :: Model
          TYPE(Mesh_t), POINTER :: Mesh
          REAL(KIND=dp) :: Quant(:), Indicator(2), Fnorm
          INTEGER :: Perm(:)
        END FUNCTION ElastInsideResidual
     END INTERFACE


!------------------------------------------------------------------------------
!    Check if version number output is requested
!------------------------------------------------------------------------------
     IF ( .NOT. AllocationsDone ) THEN
       IF ( ListGetLogical( GetSimulation(), 'Output Version Numbers', GotIt ) ) THEN
         CALL Info( 'ElasticSolve', 'ElasticSolve version:', Level = 0 ) 
         CALL Info( 'ElasticSolve', VersionID, Level = 0 ) 
         CALL Info( 'ElasticSolve', ' ', Level = 0 ) 
       END IF
     END IF


!------------------------------------------------------------------------------
!    Get variables needed for solution
!------------------------------------------------------------------------------
     IF ( .NOT. ASSOCIATED( Solver % Matrix ) ) RETURN

     dim = CoordinateSystemDimension()
     CoordinateSystem = CurrentCoordinateSystem()

     StressSol => VariableGet( Solver % Mesh % Variables, Solver % Variable % Name )
     StressPerm     => StressSol % Perm
     STDOFs         =  StressSol % DOFs
     Displacement   => StressSol % Values

     LocalNodes = COUNT( StressPerm > 0 )
     IF ( LocalNodes <= 0 ) RETURN

     TempSol => VariableGet( Solver % Mesh % Variables, 'Temperature' )
     IF ( ASSOCIATED( TempSol) ) THEN
       TempPerm    => TempSol % Perm
       Temperature => TempSol % Values
     END IF

     FlowSol => VariableGet( Solver % Mesh % Variables, 'Flow Solution' )
     IF ( ASSOCIATED( FlowSol) ) THEN
       FlowPerm => FlowSol % Perm
       k = SIZE( FlowSol % Values )
       FlowSolution => FlowSol % Values
     END IF

     MeshDisplacementActive = ListGetLogical( Solver % Values, &
                 'Displace Mesh', GotIt )
     IF ( .NOT. GotIt) MeshDisplacementActive = .TRUE.

     IF ( AllocationsDone .AND. MeshDisplacementActive ) THEN
        CALL DisplaceMesh( Solver % Mesh, Displacement, -1, StressPerm, STDOFs )
     END IF

     StiffMatrix => Solver % Matrix
     ForceVector => StiffMatrix % RHS
     UNorm = Solver % Variable % Norm
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!     Allocate some permanent storage, this is done first time only
!------------------------------------------------------------------------------
     IF ( .NOT. AllocationsDone .OR. Solver %  Mesh % Changed ) THEN
       N = Solver % Mesh % MaxElementNodes

       IF ( AllocationsDone ) THEN
          DEALLOCATE( &
                 ElementNodes % x, &
                 ElementNodes % y, &
                 ElementNodes % z, &
                 ParentNodes % x, &
                 ParentNodes % y, &
                 ParentNodes % z, &
                 FlowNodes % x, &
                 FlowNodes % y, &
                 FlowNodes % z, &
                 BoundaryDispl, &
                 ReferenceTemperature, &
                 HeatExpansionCoeff, &
                 LocalTemperature, &
                 Pressure, Velocity, &
                 ElasticModulus, PoissonRatio, &
                 Density, Damping, &
                 LocalForce, Viscosity, &
                 LocalMassMatrix,  &
                 LocalStiffMatrix,  &
                 LocalDampMatrix,  &
                 LoadVector, Alpha, Beta, &
                 LocalDisplacement )
       END IF

       ALLOCATE( &
                 ElementNodes % x( N ), &
                 ElementNodes % y( N ), &
                 ElementNodes % z( N ), &
                 ParentNodes % x( N ), &
                 ParentNodes % y( N ), &
                 ParentNodes % z( N ), &
                 FlowNodes % x( N ), &
                 FlowNodes % y( N ), &
                 FlowNodes % z( N ), &
                 BoundaryDispl( N ), &
                 ReferenceTemperature( N ), &
                 HeatExpansionCoeff( 3,3,N ), &
                 LocalTemperature( N ), &
                 Pressure( N ), Velocity( 3,N ), &
                 ElasticModulus( N ), PoissonRatio( N ), &
                 Density( N ), Damping( N ), &
                 LocalForce( STDOFs*N ), Viscosity( N ), &
                 LocalMassMatrix(  STDOFs*N,STDOFs*N ),  &
                 LocalStiffMatrix( STDOFs*N,STDOFs*N ),  &
                 LocalDampMatrix( STDOFs*N,STDOFs*N ),  &
                 LoadVector( 4,N ), Alpha( 3,N ), Beta( N ), &
                 LocalDisplacement( 3,N ), STAT=istat )

       IF ( istat /= 0 ) THEN
         CALL Fatal( 'ElasticSolve',  'Memory allocation error.' )
       END IF


!------------------------------------------------------------------------------
!    Check for normal/tangetial coordinate system defined velocities
!------------------------------------------------------------------------------
       CALL CheckNormalTangentialBoundary( Model, &
        'Normal-Tangential Displacement',NumberOfBoundaryNodes, &
          BoundaryReorder, BoundaryNormals, BoundaryTangent1, &
             BoundaryTangent2, dim )

!      Add the stress tensor components to the variable list ???????????????????
!       PSolver => Solver
!       call VariableAdd( PSolver % Mesh % Variables, PSolver % Mesh, PSolver, &
!            'Stress 11', 1, Displacement)

!------------------------------------------------------------------------------
       AllocationsDone = .TRUE.
     END IF

!------------------------------------------------------------------------------
!    Do some additional initialization, and go for it
!------------------------------------------------------------------------------
!    Work => ListGetConstRealArray( Model % Constants,'Gravity',GotIt )
!    IF ( GotIt ) THEN
!      Gravity = Work(1,1:3)*Work(1,4)
!    ELSE
!      Gravity    =  0.0D0
!      Gravity(2) = -9.81D0
!    END IF
!------------------------------------------------------------------------------
     NonlinearTol = ListGetConstReal( Solver % Values, &
        'Nonlinear System Convergence Tolerance' )

     NewtonTol = ListGetConstReal( Solver % Values, &
        'Nonlinear System Newton After Tolerance' )

     NewtonIter = ListGetInteger( Solver % Values, &
        'Nonlinear System Newton After Iterations' )

     NonlinearIter = ListGetInteger( Solver % Values, &
         'Nonlinear System Max Iterations',GotIt )

     IF ( .NOT.GotIt ) NonlinearIter = 1

     LinearModel = ListGetLogical( Solver % Values, &
          'Elasticity Solver Linear', GotIt )

     IF( ListGetLogical( Solver % Values, 'Eigen Analysis',GotIt) ) &
          LinearModel = .TRUE.

     EquationName = ListGetString( Solver % Values, 'Equation' )
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------

     DO iter=1,NonlinearIter

       at  = CPUTime()
       at0 = RealTime()

       CALL Info( 'ElasticSolve', ' ', Level=4 )
       CALL Info( 'ElasticSolve', ' ', Level=4 )
       CALL Info( 'ElasticSolve', &
           '-------------------------------------', Level=4 )
       WRITE( Message, * ) 'ELASTICITY ITERATION   ', iter
       CALL Info( 'ElasticSolve', Message, Level=4 )
       CALL Info( 'ElasticSolve', &
           '-------------------------------------', Level=4 )
       CALL Info( 'ElasticSolve', ' ', Level=4 )
       CALL Info( 'ElasticSolve', 'Starting assembly...', Level=4 )
!------------------------------------------------------------------------------
!      Compute average normals for boundaries having the normal & tangential
!      field components specified on the boundaries
!------------------------------------------------------------------------------
       IF ( NumberOfBoundaryNodes > 0 ) THEN
          CALL AverageBoundaryNormals( Model, &
               'Normal-Tangential Displacement', NumberOfBoundaryNodes, &
            BoundaryReorder, BoundaryNormals, BoundaryTangent1, &
               BoundaryTangent2, dim )
       END IF
!------------------------------------------------------------------------------
       CALL InitializeToZero( StiffMatrix, ForceVector )
!------------------------------------------------------------------------------
       t = 1
       DO t=1,Solver % NumberOfActiveElements

         IF ( RealTime() - at0 > 1.0 ) THEN
           WRITE(Message,'(a,i3,a)' ) '   Assembly: ', INT(100.0 - 100.0 * &
            (Solver % NumberOfActiveElements-t) / &
               (1.0*Solver % NumberOfActiveElements)), ' % done'
                       
           CALL Info( 'ElasticSolve', Message, Level=5 )

           at0 = RealTime()
         END IF
!------------------------------------------------------------------------------
!        Check if this element belongs to a body where displacements
!        should be calculated
!------------------------------------------------------------------------------
           CurrentElement => Solver % Mesh % Elements(Solver % ActiveElements(t))
!
!          IF ( .NOT. CheckElementEquation( Model, &
!               CurrentElement, EquationName ) ) CYCLE
!------------------------------------------------------------------------------
!        Ok, we�ve got one for stress computations
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!        Set also the current element pointer in the model structure to
!        reflect the element being processed
!------------------------------------------------------------------------------
         Model % CurrentElement => Solver % Mesh % Elements(t)
!------------------------------------------------------------------------------
         body_id = CurrentElement % BodyId
         n = CurrentElement % TYPE % NumberOfNodes
         NodeIndexes => CurrentElement % NodeIndexes

         eq_id = ListGetInteger( Model % Bodies(body_id) % Values, 'Equation', &
              minv=1, maxv=Model % NumberOfEquations )
         PlaneStress = ListGetLogical( Model % Equations(eq_id) % Values, &
                         'Plane Stress',gotIt )

         ElementNodes % x(1:n) = Solver % Mesh % Nodes % x(NodeIndexes)
         ElementNodes % y(1:n) = Solver % Mesh % Nodes % y(NodeIndexes)
         ElementNodes % z(1:n) = Solver % Mesh % Nodes % z(NodeIndexes)

         k = ListGetInteger( Model % Bodies(body_id) % Values,'Material', &
                   minv=1, maxv=Model % NumberOFMaterials )
         Material => Model % Materials(k) % Values

         ElasticModulus(1:n) = ListGetReal( Material, &
              'Youngs Modulus',n,NodeIndexes )

         PoissonRatio(1:n) = ListGetReal( Material, &
              'Poisson Ratio',n,NodeIndexes )

         Density(1:n) = ListGetReal( Material, &
              'Density',n,NodeIndexes,GotIt )

         Damping(1:n) = ListGetReal( Material, &
              'Damping',n,NodeIndexes,GotIt )

         HeatExpansionCoeff   = 0.0D0
         DO i=1,3
           HeatExpansionCoeff(i,i,1:n) = ListGetReal( Material,&
             'Heat Expansion Coefficient',n,NodeIndexes,gotIt )
         END DO

         ReferenceTemperature(1:n) = ListGetReal( Material, &
            'Reference Temperature',n,NodeIndexes,gotIt )

!------------------------------------------------------------------------------
!        Set body forces
!------------------------------------------------------------------------------
         bf_id = ListGetInteger( Model % Bodies(body_id) % Values, &
             'Body Force',gotIt, 1, Model % NumberOFBodyForces)

         LoadVector = 0.0D0

         IF ( gotit ) THEN
           LoadVector(1,1:n) = LoadVector(1,1:n) + ListGetReal( &
            Model % BodyForces(bf_id) % Values, &
                       'Stress Bodyforce 1',n,NodeIndexes,gotIt )

           LoadVector(2,1:n) = LoadVector(2,1:n) + ListGetReal( &
            Model % BodyForces(bf_id) % Values, &
                       'Stress Bodyforce 2',n,NodeIndexes,gotIt )

           IF ( STDOFs > 2 ) THEN
             LoadVector(3,1:n) = LoadVector(3,1:n) + ListGetReal( &
              Model % BodyForces(bf_id) % Values, &
                       'Stress Bodyforce 3',n,NodeIndexes,gotIt )
           END IF
         END IF


!------------------------------------------------------------------------------
!        Get element local stiffness & mass matrices
!------------------------------------------------------------------------------
         LocalTemperature = 0.0D0
         IF ( ASSOCIATED(TempSol) ) THEN
           DO i=1,n
             k = TempPerm(NodeIndexes(i))
             LocalTemperature(i) = Temperature(k) - ReferenceTemperature(i)
           END DO
         ELSE
           LocalTemperature(1:n) = 0.0d0
         END IF         

         LocalDisplacement = 0.0D0
         DO i=1,n
            k = StressPerm(NodeIndexes(i))
            DO j=1,STDOFs
               LocalDisplacement(j,i) = Displacement(STDOFs*(k-1)+j)
            END DO
         END DO

         IF( LinearModel ) LocalDisplacement = 0.0d0

         IF ( CoordinateSystem == Cartesian ) THEN
            CALL StressCompose( LocalMassMatrix, LocalDampMatrix, &
              LocalStiffMatrix,LocalForce, LoadVector, ElasticModulus, &
                PoissonRatio,Density,Damping,PlaneStress,HeatExpansionCoeff, &
                LocalTemperature,CurrentElement,n,ElementNodes,LocalDisplacement )
         ELSE
            CALL StressGeneralCompose( LocalMassMatrix, LocalDampMatrix, &
              LocalStiffMatrix,LocalForce, LoadVector, ElasticModulus, &
                PoissonRatio,Density,Damping,PlaneStress,HeatExpansionCoeff, &
                LocalTemperature,CurrentElement,n,ElementNodes,LocalDisplacement )
         END IF
         

!------------------------------------------------------------------------------
!        If time dependent simulation, add mass matrix to global 
!        matrix and global RHS vector
!------------------------------------------------------------------------------
         IF ( TransientSimulation .AND. Solver % NOFEigenValues <= 0 )  THEN
!
!           get the solution from previous iteration for nodes of this element
!------------------------------------------------------------------------------
!          NOTE: the following will replace LocalStiffMatrix and LocalForce
!          with the combined information
!------------------------------------------------------------------------------
           CALL Add2ndOrderTime( LocalMassMatrix, LocalDampMatrix, &
                LocalStiffMatrix, LocalForce, dt, n, STDOFs, &
                StressPerm(NodeIndexes), Solver )

         END IF
!------------------------------------------------------------------------------
!        If boundary fields have been defined in normal/tangential
!        coordinate systems, we�ll have to rotate the matrix & force vector
!        to that coordinate system
!------------------------------------------------------------------------------

         IF ( NumberOfBoundaryNodes > 0 ) THEN
           CALL RotateMatrix( LocalStiffMatrix,LocalForce,n,STDOFs,STDOFs, &
            BoundaryReorder(NodeIndexes),BoundaryNormals,BoundaryTangent1, &
                              BoundaryTangent2 )
         END IF

!------------------------------------------------------------------------------
!        Update global matrices from local matrices 
!------------------------------------------------------------------------------
         CALL UpdateGlobalEquations( StiffMatrix, LocalStiffMatrix, &
           ForceVector, LocalForce, n, STDOFs, StressPerm(NodeIndexes) )

         IF ( Solver % NOFEigenValues > 0 ) THEN
            CALL DefaultUpdateMass( LocalMassMatrix )
            CALL DefaultUpdateDamp( LocalDampMatrix )
         END IF
!------------------------------------------------------------------------------
      END DO

      CALL Info( 'ElasticSolve', 'Assembly done', Level=4 )

!------------------------------------------------------------------------------
!     Neumann & Newton boundary conditions
!------------------------------------------------------------------------------
      DO t = Solver % Mesh % NumberOfBulkElements+1, &
               Solver % Mesh % NumberOfBulkElements + &
                   Solver % Mesh % NumberOfBoundaryElements

        CurrentElement => Solver % Mesh % Elements(t)

!------------------------------------------------------------------------------
!        Set also the current element pointer in the model structure to
!        reflect the element being processed
!------------------------------------------------------------------------------
        Model % CurrentElement => Solver % Mesh % Elements(t)
!------------------------------------------------------------------------------
        n = CurrentElement % TYPE % NumberOfNodes
        NodeIndexes => CurrentElement % NodeIndexes

        IF ( ANY( StressPerm( NodeIndexes ) <= 0 ) ) CYCLE
!
!       The element type 101 (point element) can only be used
!       to set Dirichlet BCs, so skip �em.
!
        IF ( CurrentElement % TYPE % ElementCode /= 101 ) THEN

        ElementNodes % x(1:n) = Solver % Mesh % Nodes % x(NodeIndexes)
        ElementNodes % y(1:n) = Solver % Mesh % Nodes % y(NodeIndexes)
        ElementNodes % z(1:n) = Solver % Mesh % Nodes % z(NodeIndexes)

        DO i=1,Model % NumberOfBCs
          IF ( CurrentElement % BoundaryInfo % Constraint == &
                   Model % BCs(i) % Tag ) THEN
!------------------------------------------------------------------------------
!------------------------------------------------------------------------------
            LoadVector = 0.0D0
            Alpha      = 0.0D0
            Beta       = 0.0D0
!------------------------------------------------------------------------------
!           Force in given direction BC: \tau\cdot n = F
!------------------------------------------------------------------------------
            GotForceBC = .FALSE.
            LoadVector(1,1:n) =  ListGetReal( Model % BCs(i) % Values, &
                      'Force 1',n,NodeIndexes,gotIt )
            GotForceBC = GotForceBC.OR.gotIt

            LoadVector(2,1:n) =  ListGetReal( Model % BCs(i) % Values, &
                      'Force 2',n,NodeIndexes,gotIt )
            GotForceBC = GotForceBC.OR.gotIt

            LoadVector(3,1:n) =  ListGetReal( Model % BCs(i) % Values, &
                      'Force 3',n,NodeIndexes,gotIt )
            GotForceBC = GotForceBC.OR.gotIt

            Beta(1:n) =  ListGetReal( Model % BCs(i) % Values, &
                      'Normal Force',n,NodeIndexes,gotIt )
            GotForceBC = GotForceBC.OR.gotIt

            GotForceBC = GotForceBC .OR. ListGetLogical( &
                  Model % BCs(i) % Values, 'Force BC', GotIt )

            GotForceBC = GotForceBC .OR. ListGetLogical( &
                  Model % BCs(i) % Values, 'FSI BC', GotIt )

            IF ( .NOT.GotForceBC ) CYCLE

!------------------------------------------------------------------------------

           AdjacentElement = CurrentElement % BoundaryInfo % LElement

           IF ( AdjacentElement < 1 ) THEN
             AdjacentElement = CurrentElement % BoundaryInfo % RElement
           ELSE
             ParentElement => Solver % Mesh % Elements( AdjacentElement )
             IF ( ANY(StressPerm(ParentElement % NodeIndexes)==0 )) THEN
               AdjacentElement = CurrentElement % BoundaryInfo % RElement
             END IF
           END IF

           ParentElement => Solver % Mesh % Elements( AdjacentElement )
           k = ParentElement % TYPE % NumberOfNodes
           AdjacentNodes => ParentElement % NodeIndexes

           ParentNodes % x(1:k) = Solver % Mesh % Nodes % x(AdjacentNodes)
           ParentNodes % y(1:k) = Solver % Mesh % Nodes % y(AdjacentNodes)
           ParentNodes % z(1:k) = Solver % Mesh % Nodes % z(AdjacentNodes)

           LocalDisplacement = 0.0D0
           DO l=1,ParentElement % TYPE % NumberOfNodes
              k = StressPerm(AdjacentNodes(l))
              DO j=1,STDOFs
                LocalDisplacement(j,l) = Displacement(STDOFs*(k-1)+j)
              END DO
           END DO

           NULLIFY( FlowElement )
           FlowNOFNodes = 1

           IF ( ASSOCIATED( FlowSol  ) ) THEN
             AdjacentElement = CurrentElement % BoundaryInfo % LElement

             IF ( AdjacentElement < 1 ) THEN
               AdjacentElement = CurrentElement % BoundaryInfo % RElement
             ELSE
               FlowElement => Solver % Mesh % Elements( AdjacentElement )
               IF ( ANY(FlowPerm(FlowElement % NodeIndexes)==0 )) THEN
                 AdjacentElement = CurrentElement % BoundaryInfo % RElement
               END IF
               NULLIFY(FlowElement)
             END IF

             IF ( AdjacentElement > 0 ) THEN
                FlowNOFNodes = 0
                FlowElement => Solver % Mesh % Elements( AdjacentElement )
                FlowNOFNodes = FlowElement % TYPE % NumberOfNodes
                AdjacentNodes => FlowElement % NodeIndexes
                
                FlowNodes % x(1:FlowNOFNodes) = Solver % Mesh % Nodes % x(AdjacentNodes)
                FlowNodes % y(1:FlowNOFNodes) = Solver % Mesh % Nodes % y(AdjacentNodes)
                FlowNodes % z(1:FlowNOFNodes) = Solver % Mesh % Nodes % z(AdjacentNodes)
                
                DO j=1,FlowNOFNodes
                   k = StressPerm(AdjacentNodes(j))
                   IF ( k /= 0 ) THEN
                      k = STDOFs*(k-1)
                      FlowNodes % x(j) = FlowNodes % x(j) + Displacement( k+1 )
                      
                      IF ( STDOFs > 1 ) &
                           FlowNodes % y(j) = FlowNodes % y(j) + Displacement( k+2 )
                      
                      IF ( STDOFs > 2 ) &
                           FlowNodes % z(j) = FlowNodes % z(j) + Displacement( k+3 )
                   END IF
                END DO
                
                Velocity = 0.0D0
                DO l=1,FlowNOFNodes
                   k = FlowPerm(AdjacentNodes(l))
                   DO j=1,FlowSol % DOFs-1
                      Velocity(j,l) = FlowSolution(FlowSol % DOFs*(k-1)+j)
                   END DO
                   Pressure(l) = FlowSolution(FlowSol % DOFs*k)
                END DO
                
                j = ListGetInteger( Model % Bodies(FlowElement % BodyId) &
                      % Values,'Material', minv=1, maxv=Model % NumberOFMaterials )
                Material => Model % Materials(j) % Values
                Viscosity(1:FlowNOFNodes) = ListGetReal( &
                     Material,'Viscosity',FlowNOFNodes,AdjacentNodes,gotIt )

                CompressibilityFlag = ListGetString( Material, &
                     'Compressibility Model', GotIt )

                CompressibilityDefined = .FALSE.
                IF ( GotIt ) THEN
                   IF ( CompressibilityFlag /= 'incompressible' ) THEN
                      CompressibilityDefined = .TRUE.
                   END IF
                END IF

             END IF
             
          END IF

           IF ( CoordinateSystem == Cartesian ) THEN
             CALL StressBoundary( LocalStiffMatrix,LocalForce, LoadVector,   &
              Alpha,Beta,LocalDisplacement, CurrentElement,n,ElementNodes,   &
               ParentElement, ParentElement % TYPE % NumberOfNodes,          &
                ParentNodes, FlowElement, FlowNOFNodes, FlowNodes,Velocity,  &
                 Pressure,Viscosity,Density,CompressibilityDefined )

           ELSE
             CALL StressGeneralBoundary( LocalStiffMatrix,LocalForce, LoadVector,   &
              Alpha,Beta,LocalDisplacement, CurrentElement,n,ElementNodes,   &
               ParentElement, ParentElement % TYPE % NumberOfNodes,          &
                ParentNodes, FlowElement, FlowNOFNodes, FlowNodes,Velocity,  &
                 Pressure,Viscosity,Density,CompressibilityDefined )
!             CALL StressGeneralBoundary( LocalStiffMatrix, &
!              LocalForce,LoadVector,Alpha,Beta,CurrentElement,n,ElementNodes )
           END IF

!------------------------------------------------------------------------------
!          If boundary fields have been defined in normal/tangetial coordinate
!          systems, we have to rotate the matrix & force vector to that
!          coordinate system
!------------------------------------------------------------------------------
            IF ( NumberOfBoundaryNodes > 0 ) THEN
              CALL RotateMatrix( LocalStiffMatrix,LocalForce,n,STDOFs,STDOFs, &
               BoundaryReorder(NodeIndexes),BoundaryNormals,BoundaryTangent1, &
                                 BoundaryTangent2 )
            END IF
!------------------------------------------------------------------------------
!           Update global matrices from local matrices (will also affect
!           LocalStiffMatrix and LocalForce if transientsimulation is on).
!------------------------------------------------------------------------------
            IF ( TransientSimulation .AND. Solver % NOFEigenValues <= 0 ) THEN
              CALL UpdateTimeForce( StiffMatrix,ForceVector,LocalForce, &
                        n,STDOFs, StressPerm(NodeIndexes) )
            END IF

            CALL UpdateGlobalEquations( StiffMatrix, LocalStiffMatrix, &
              ForceVector, LocalForce, n, STDOFs, StressPerm(NodeIndexes) )

!------------------------------------------------------------------------------
          END IF
        END DO
        END IF
      END DO
!------------------------------------------------------------------------------

      CALL FinishAssembly( Solver, ForceVector )

!------------------------------------------------------------------------------
!     Dirichlet boundary conditions
!------------------------------------------------------------------------------
      WRITE( str, '(a,a,i1)' ) TRIM(Solver % Variable % Name),' ',1
      CALL SetDirichletBoundaries( Model, StiffMatrix, ForceVector, &
               str, 1, STDOFs, StressPerm )

      WRITE( str, '(a,a,i1)' ) TRIM(Solver % Variable % Name),' ',2
      CALL SetDirichletBoundaries( Model, StiffMatrix, ForceVector, &
               str, 2, STDOFs,StressPerm )

      IF ( STDOFs >= 3 ) THEN
        WRITE( str, '(a,a,i1)' ) TRIM(Solver % Variable % Name),' ',3
        CALL SetDirichletBoundaries( Model, StiffMatrix, ForceVector, &
                 str, 3, STDOFs, StressPerm )
      END IF
!------------------------------------------------------------------------------

      CALL Info( 'ElasticSolve', 'Set boundaries done', Level=4 )

!------------------------------------------------------------------------------
!     Solve the system and check for convergence
!------------------------------------------------------------------------------
      PrevUNorm = Unorm

      CALL SolveSystem( StiffMatrix, ParMatrix, ForceVector, &
               Displacement, UNorm, STDOFs, Solver )

      IF ( PrevUNorm + UNorm == 0.0d0 ) THEN
         RelativeChange = 0.0d0
      ELSE
         RelativeChange = 2.0d0 * ABS( PrevUNorm - UNorm) / (PrevUNorm + UNorm)
      END IF

      WRITE( Message, * ) 'Result Norm   : ',UNorm
      CALL Info( 'ElasticSolve', Message, Level=4 )
      WRITE( Message, * ) 'Relative Change : ',RelativeChange
      CALL Info( 'ElasticSolve', Message, Level=4 )

!------------------------------------------------------------------------------
!     If boundary fields have been defined in normal/tangential coordinate
!     systems, we�ll have to rotate the solution back to coordinate axis
!     directions
!------------------------------------------------------------------------------
      IF ( NumberOfBoundaryNodes > 0 ) THEN
        DO i=1,Solver % Mesh % NumberOfNodes
          k = BoundaryReorder(i)

          IF ( k > 0 ) THEN
            j = StressPerm(i)

            IF ( j > 0 ) THEN
              IF ( STDOFs < 3 ) THEN
                Bu = Displacement( STDOFs*(j-1)+1 )
                Bv = Displacement( STDOFs*(j-1)+2 )

                Displacement( STDOFs*(j-1)+1) = BoundaryNormals(k,1) * Bu - &
                                BoundaryNormals(k,2) * Bv

                Displacement( STDOFs*(j-1)+2) = BoundaryNormals(k,2) * Bu + &
                                BoundaryNormals(k,1) * Bv
              ELSE
                Bu = Displacement( STDOFs*(j-1)+1 )
                Bv = Displacement( STDOFs*(j-1)+2 )
                Bw = Displacement( STDOFs*(j-1)+3 )

                RM(1,:) = BoundaryNormals(k,:)
                RM(2,:) = BoundaryTangent1(k,:)
                RM(3,:) = BoundaryTangent2(k,:)
                CALL InvertMatrix( RM,3 )

                Displacement(STDOFs*(j-1)+1) = RM(1,1)*Bu+RM(1,2)*Bv+RM(1,3)*Bw
                Displacement(STDOFs*(j-1)+2) = RM(2,1)*Bu+RM(2,2)*Bv+RM(2,3)*Bw
                Displacement(STDOFs*(j-1)+3) = RM(3,1)*Bu+RM(3,2)*Bv+RM(3,3)*Bw
              END IF
            END IF
          END IF
        END DO 
      END IF

!------------------------------------------------------------------------------
      IF ( RelativeChange < NewtonTol .OR. &
             iter > NewtonIter ) NewtonLinearization = .TRUE.

      IF ( RelativeChange < NonLinearTol ) EXIT

!------------------------------------------------------------------------------
    END DO ! of nonlinear iter
!------------------------------------------------------------------------------

    IF ( ListGetLogical(Solver % Values, 'Adaptive Mesh Refinement', GotIt) ) THEN
       CALL RefineMesh( Model, Solver, Displacement, StressPerm, &
            ElastInsideResidual, ElastEdgeResidual, ElastBoundaryResidual )

       IF ( MeshDisplacementActive ) THEN
         StressSol => Solver % Variable
         IF ( .NOT.ASSOCIATED( Solver % Mesh, Model % Mesh ) ) &
            CALL DisplaceMesh( Solver % Mesh, StressSol % Values, 1, &
                  StressSol % Perm, StressSol % DOFs, .FALSE. )
       END IF
    END IF
    
    IF ( MeshDisplacementActive ) THEN
      CALL DisplaceMesh( Model % Mesh, Displacement, 1, &
                StressPerm, STDOFs, .FALSE. )
    END IF

!==============================================================================

    CONTAINS


!------------------------------------------------------------------------------
   SUBROUTINE StressCompose( MassMatrix,DampMatrix,StiffMatrix,ForceVector, &
        LoadVector, NodalYoung, NodalPoisson, NodalDensity, NodalDamping, &
        PlaneStress,NodalHeatExpansion, NodalTemperature, Element,n,Nodes, &
        NodalDisplacement )
!DLLEXPORT StressCompose
!------------------------------------------------------------------------------

     REAL(KIND=dp) :: StiffMatrix(:,:),MassMatrix(:,:),DampMatrix(:,:), &
          NodalHeatExpansion(:,:,:)
     REAL(KIND=dp) :: NodalTemperature(:),NodalDensity(:), &
                NodalDamping(:),LoadVector(:,:)
     REAL(KIND=dp) :: NodalDisplacement(:,:)
     REAL(KIND=dp), DIMENSION(:) :: ForceVector,NodalPoisson,NodalYoung

     LOGICAL :: PlaneStress

     TYPE(Element_t) :: Element
     TYPE(Nodes_t) :: Nodes

     INTEGER :: n
!------------------------------------------------------------------------------
!
     REAL(KIND=dp) :: Basis(n),ddBasisddx(1,1,1)
     REAL(KIND=dp) :: dBasisdx(n,3),SqrtElementMetric

     REAL(KIND=dp) :: Force(3),NodalLame1(n),NodalLame2(n),Density, &
          Damping,Lame1,Lame2
     REAL(KIND=dp) :: Grad(3,3),Identity(3,3),DetDefG,CofG(3,3),TrueForce(3)
     REAL(KIND=dp) ::  DefG(3,3), Strain(3,3), Stress2(3,3), Stress1(3,3)
     REAL(KIND=dp) :: dDefG(3,3),dStrain(3,3),dStress2(3,3),dStress1(3,3)
     REAL(KIND=dp) :: dDefGU(3,3),dStrainU(3,3),dStress2U(3,3),dStress1U(3,3)

     REAL(KIND=dp) :: Load(3),Temperature, GradBasis(3,3)
     REAL(KIND=dp), DIMENSION(3,3) :: HeatExpansion

     INTEGER :: i,j,k,l,p,q,t,dim

     REAL(KIND=dp) :: s,u,v,w
  
     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff

     INTEGER :: N_Integ

     REAL(KIND=dp), DIMENSION(:), POINTER :: U_Integ,V_Integ,W_Integ,S_Integ

     LOGICAL :: stat
!------------------------------------------------------------------------------

     dim = CoordinateSystemDimension()

     IF ( PlaneStress ) THEN
       NodalLame1(1:n) = NodalYoung(1:n) * NodalPoisson(1:n) /  &
            ( (1.0d0 - NodalPoisson(1:n)**2) )
     ELSE
       NodalLame1(1:n) = NodalYoung(1:n) * NodalPoisson(1:n) /  &
          (  (1.0d0 + NodalPoisson(1:n)) * (1.0d0 - 2.0d0*NodalPoisson(1:n)) )
     END IF

     NodalLame2(1:n) = NodalYoung(1:n)  / ( 2* (1.0d0 + NodalPoisson(1:n)) )

     ForceVector = 0.0D0
     StiffMatrix = 0.0D0
     MassMatrix  = 0.0D0
     DampMatrix  = 0.0d0

     Identity = 0.0D0
     DO i = 1,dim
        Identity(i,i) = 1.0D0
     END DO
!    
!    Integration stuff
!    
     SELECT CASE(Element % TYPE % ElementCode/100)

!       Line segments:
!       --------------
        CASE( 2 )
        SELECT CASE( n )
           CASE( 2 )
           IntegStuff = GaussPoints( element,1 )
           CASE( 3 )
           IntegStuff = GaussPoints( element,4 )
           CASE( 4 )
           IntegStuff = GaussPoints( element,5 )
           CASE DEFAULT
           CALL Fatal( 'ElasticSolve',  'Unknown number of nodes.' )
        END SELECT

!       Triangles:
!       ----------
        CASE( 3 )
        SELECT CASE( n )
           CASE( 3 )
           IntegStuff = GaussPoints( element,1 )
           CASE( 6 )
           IntegStuff = GaussPoints( element,7 )
           CASE( 10 )
           IntegStuff = GaussPoints( element,17 )
           CASE DEFAULT
           CALL Fatal( 'ElasticSolve',  'Unknown number of nodes.' )
        END SELECT

!       Quadrilaterals:
!       ---------------
        CASE( 4 )
        SELECT CASE( n )
           CASE( 4 )
           IntegStuff = GaussPoints( element,4 )
           CASE( 8,9 )
           IntegStuff = GaussPoints( element,16 )
           CASE( 12,16 )
           IntegStuff = GaussPoints( element,25 )
           CASE DEFAULT
           CALL Fatal( 'ElasticSolve',  'Unknown number of nodes.' )
        END SELECT

!       Tetrahedrons:
!       -------------
        CASE( 5 )
        SELECT CASE( n )
           CASE( 4 )
           IntegStuff = GaussPoints( element,1 )
           CASE( 10 )
           IntegStuff = GaussPoints( element,11 )
           CASE DEFAULT
           CALL Fatal( 'ElasticSolve',  'Unknown number of nodes.' )
        END SELECT

!       Octahedrons:
!       ------------
        CASE( 8 )
        SELECT CASE( n )
           CASE( 8 )
           IntegStuff = GaussPoints( element,8 )
           CASE( 20,27 )
           IntegStuff = GaussPoints( element,64 )
           CASE DEFAULT
           CALL Fatal( 'ElasticSolve',  'Unknown number of nodes.' )
        END SELECT

!       Others:
!       -------
        CASE DEFAULT
           CALL Fatal( 'ElasticSolve',  'Unknown element type.' )

     END SELECT

     U_Integ => IntegStuff % u
     V_Integ => IntegStuff % v
     W_Integ => IntegStuff % w
     S_Integ => IntegStuff % s
     N_Integ =  IntegStuff % n
!
!   Now we start integrating
!
    DO t=1,N_Integ

      u = U_Integ(t)
      v = V_Integ(t)
      w = W_Integ(t)

!------------------------------------------------------------------------------
!     Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
      stat = ElementInfo( Element,Nodes,u,v,w,SqrtElementMetric, &
                 Basis,dBasisdx,ddBasisddx,.FALSE. )

      s = SqrtElementMetric * S_Integ(t)

!------------------------------------------------------------------------------
!  
!     Force at integration point
!   
      Force = 0.0D0
      DO i=1,dim
        Force(i) = SUM( LoadVector(i,1:n)*Basis )
      END DO
!
!     Lame parameters at the integration point
!
      Lame1 = SUM( NodalLame1(1:n)*Basis )
      Lame2 = SUM( NodalLame2(1:n)*Basis )
      Density = SUM( NodalDensity(1:n)*Basis )
      Damping = SUM( NodalDamping(1:n)*Basis )
!
!     Temperature at the integration point
!
      Temperature = SUM( NodalTemperature(1:n)*Basis )
!
!     Heat expansion tensor values at the integration point
!
!      DO i=1,3
!        DO j=1,3
!          HeatExpansion(i,j) = SUM( NodalHeatExpansion(i,j,1:n)*Basis )
!        END DO
!      END DO

!===========================================================================
!
!                       S T I F F N E S S   M A T R I X 
!
!                                    A N D
!
!                   R E S I D U A L   F O R C E   V E C T O R
!
!===========================================================================

!      The current solution:
!      ---------------------
       Grad = MATMUL(NodalDisplacement(:,1:n),dBasisdx)
       DefG = Identity + Grad
       Strain = (TRANSPOSE(Grad)+Grad+MATMUL(TRANSPOSE(Grad),Grad))/2.0D0
       Stress2 = 2.0D0*Lame2*Strain + Lame1*TRACE(Strain,dim)*Identity
       Stress1 = MATMUL(DefG,Stress2)

       SELECT CASE( dim )
          CASE( 1 )
          DetDefG = DefG(1,1)
          CASE( 2 )
          DetDefG = DefG(1,1)*DefG(2,2) - DefG(1,2)*DefG(2,1)
          CASE( 3 )
          DetDefG = DefG(1,1) * ( DefG(2,2)*DefG(3,3) - DefG(2,3)*DefG(3,2) ) + &
                    DefG(1,2) * ( DefG(2,3)*DefG(3,1) - DefG(2,1)*DefG(3,3) ) + &
                    DefG(1,3) * ( DefG(2,1)*DefG(3,2) - DefG(2,2)*DefG(3,1) )
       END SELECT

!      Gateaux derivatives of the solution with respect to the displacement:
!      ---------------------------------------------------------------------
       dDefGU = Grad
       dStrainU = (MATMUL(TRANSPOSE(DefG),dDefGU) &
            + MATMUL(TRANSPOSE(dDefGU),DefG))/2.0D0
       dStress2U = 2.0D0*Lame2*dStrainU + Lame1*TRACE(dStrainU,dim)*Identity
       dStress1U = MATMUL(dDefGU,Stress2) + MATMUL(DefG,dStress2U)

!      Loop over the test functions (stiffness matrix):
!      ------------------------------------------------
       DO p = 1,N
          DO i = 1,dim

!            Gateaux derivatives of the solution with respect to the test functions:
!            -----------------------------------------------------------------------
             dDefG = 0.0D0; dDefG(i,:) = dBasisdx(p,:)
             dStrain = (MATMUL(TRANSPOSE(DefG),dDefG) &
                  + MATMUL(TRANSPOSE(dDefG),DefG))/2.0D0
             dStress2 = 2.0D0*Lame2*dStrain + Lame1*TRACE(dStrain,dim)*Identity
             dStress1 = MATMUL(dDefG,Stress2) + MATMUL(DefG,dStress2)

             ForceVector(dim*(p-1)+i) = ForceVector(dim*(p-1)+i) &
                  +(Basis(p)*Force(i)*DetDefG &
                   -DOT_PRODUCT(dBasisdx(p,:),Stress1(i,:)) &
                   +DOT_PRODUCT(dBasisdx(p,:),dStress1U(i,:)))*s

!            Loop over the basis functions:
!            ------------------------------
             DO q = 1,N
                DO j = 1,dim

                   GradBasis = 0.0D0; GradBasis(j,:) = dBasisdx(q,:)

!                  Newton iteration:
!                  -----------------
                   StiffMatrix(dim*(p-1)+i,dim*(q-1)+j) &
                        = StiffMatrix(dim*(p-1)+i,dim*(q-1)+j) &
                        + DOT_PRODUCT(dBasisdx(q,:),dStress1(j,:))*s
!                        + DDOT_PRODUCT(dStress1,GradBasis,3)*s

!                  Fixed point iteration:
!                  ----------------------
!                   dDefG = 0.0D0; dDefG(j,:) = dBasisdx(q,:)
!                   dStrain = (MATMUL(TRANSPOSE(DefG),dDefG) &
!                        + MATMUL(TRANSPOSE(dDefG),DefG))/2.0D0
!                   StiffMatrix(dim*(p-1)+i,dim*(q-1)+j) &
!                        = StiffMatrix(dim*(p-1)+i,dim*(q-1)+j) &
!                        + DDOT_PRODUCT(dStrain,dStress2,dim)*s

                END DO
             END DO
          END DO
       END DO


!      Integrate mass matrix:
!      ----------------------
       DO p = 1,N
          DO q = 1,N
             DO i = 1,dim

                MassMatrix(dim*(p-1)+i,dim*(q-1)+i) &
                        = MassMatrix(dim*(p-1)+i,dim*(q-1)+i) &
                        + Basis(p)*Basis(q)*Density*DetDefG*s

             END DO
          END DO
       END DO

!      Utilize the Rayleigh damping:
!      -----------------------------
       DampMatrix = Damping * MassMatrix

    END DO

!------------------------------------------------------------------------------

 END SUBROUTINE StressCompose
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE StressGeneralCompose( MassMatrix,DampMatrix,StiffMatrix,ForceVector, &
        LoadVector, NodalYoung, NodalPoisson, NodalDensity, NodalDamping, &
        PlaneStress,NodalHeatExpansion, NodalTemperature, Element,n,Nodes, &
        NodalDisplacement )
!DLLEXPORT StressGeneralCompose
!------------------------------------------------------------------------------
     REAL(KIND=dp) :: StiffMatrix(:,:),MassMatrix(:,:),DampMatrix(:,:), &
          NodalHeatExpansion(:,:,:)
     REAL(KIND=dp) :: NodalTemperature(:),NodalDensity(:), &
                NodalDamping(:),LoadVector(:,:)
     REAL(KIND=dp) :: NodalDisplacement(:,:)
     REAL(KIND=dp), DIMENSION(:) :: ForceVector,NodalPoisson,NodalYoung

     LOGICAL :: PlaneStress

     TYPE(Element_t) :: Element
     TYPE(Nodes_t) :: Nodes

     INTEGER :: n
!------------------------------------------------------------------------------
!
     REAL(KIND=dp) :: Basis(n),ddBasisddx(1,1,1)
     REAL(KIND=dp) :: dBasisdx(n,3),SqrtElementMetric

     REAL(KIND=dp) :: Force(3),NodalLame1(n),NodalLame2(n),Density, &
          Damping,Lame1,Lame2
     REAL(KIND=dp) :: Grad(3,3),Identity(3,3),DetDefG,CofG(3,3),TrueForce(3)
     REAL(KIND=dp) ::  DefG(3,3), Strain(3,3), Stress2(3,3), Stress1(3,3)
     REAL(KIND=dp) :: dDefG(3,3),dStrain(3,3),dStress2(3,3),dStress1(3,3)
     REAL(KIND=dp) :: dDefGU(3,3),dStrainU(3,3),dStress2U(3,3),dStress1U(3,3)
     REAL(KIND=dp) :: Stress(3,3)

     REAL(KIND=dp) :: SqrtMetric,Metric(3,3),Symb(3,3,3),dSymb(3,3,3,3),X,Y,Z
     REAL(KIND=dp) :: Disp(3)

     REAL(KIND=dp) :: Load(3),Temperature, GradBasis(3,3)
     REAL(KIND=dp), DIMENSION(3,3) :: HeatExpansion

     INTEGER :: i,j,k,l,p,q,t,dim

     REAL(KIND=dp) :: s,u,v,w,Radius
     REAL(KIND=dp) :: Pii = 3.14159d0
  
     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff

     INTEGER :: N_Integ

     REAL(KIND=dp), DIMENSION(:), POINTER :: U_Integ,V_Integ,W_Integ,S_Integ

     LOGICAL :: stat, CylindricSymmetry
!------------------------------------------------------------------------------

     CylindricSymmetry = ( CoordinateSystem == CylindricSymmetric .OR. &
          CoordinateSystem == AxisSymmetric )

     IF( CylindricSymmetry ) THEN
        dim = 3
     ELSE
        dim = CoordinateSystemDimension()
     END IF

     IF ( PlaneStress ) THEN
       NodalLame1(1:n) = NodalYoung * NodalPoisson /  &
            ( (1.0d0 - NodalPoisson**2) )
     ELSE
       NodalLame1(1:n) = NodalYoung * NodalPoisson /  &
          (  (1.0d0 + NodalPoisson) * (1.0d0 - 2.0d0*NodalPoisson) )
     END IF

     NodalLame2(1:n) = NodalYoung  / ( 2* (1.0d0 + NodalPoisson) )

     ForceVector = 0.0D0
     StiffMatrix = 0.0D0
     MassMatrix  = 0.0D0
     DampMatrix  = 0.0d0

     Identity = 0.0D0
     DO i = 1,dim
        Identity(i,i) = 1.0D0
     END DO
!    
!    Integration stuff
!    
     SELECT CASE(Element % TYPE % ElementCode/100)

!       Line segments:
!       --------------
        CASE( 2 )
        SELECT CASE( n )
           CASE( 2 )
           IntegStuff = GaussPoints( element,1 )
           CASE( 3 )
           IntegStuff = GaussPoints( element,4 )
           CASE( 4 )
           IntegStuff = GaussPoints( element,5 )
           CASE DEFAULT
           CALL Fatal( 'ElasticSolve',  'Unknown number of nodes.' )
        END SELECT

!       Triangles:
!       ----------
        CASE( 3 )
        SELECT CASE( n )
           CASE( 3 )
           IntegStuff = GaussPoints( element,1 )
           CASE( 6 )
           IntegStuff = GaussPoints( element,7 )
           CASE( 10 )
           IntegStuff = GaussPoints( element,17 )
           CASE DEFAULT
           CALL Fatal( 'ElasticSolve',  'Unknown number of nodes.' )
        END SELECT

!       Quadrilaterals:
!       ---------------
        CASE( 4 )
        SELECT CASE( n )
           CASE( 4 )
           IntegStuff = GaussPoints( element,4 )
           CASE( 8,9 )
           IntegStuff = GaussPoints( element,16 )
           CASE( 12,16 )
           IntegStuff = GaussPoints( element,25 )
           CASE DEFAULT
           CALL Fatal( 'ElasticSolve',  'Unknown number of nodes.' )
        END SELECT

!       Tetrahedrons:
!       -------------
        CASE( 5 )
        SELECT CASE( n )
           CASE( 4 )
           IntegStuff = GaussPoints( element,1 )
           CASE( 10 )
           IntegStuff = GaussPoints( element,11 )
           CASE DEFAULT
           CALL Fatal( 'ElasticSolve',  'Unknown number of nodes.' )
        END SELECT

!       Octahedrons:
!       ------------
        CASE( 8 )
        SELECT CASE( n )
           CASE( 8 )
           IntegStuff = GaussPoints( element,8 )
           CASE( 20,27 )
           IntegStuff = GaussPoints( element,64 )
           CASE DEFAULT
           CALL Fatal( 'ElasticSolve',  'Unknown number of nodes.' )
        END SELECT

!       Others:
!       -------
        CASE DEFAULT
           CALL Fatal( 'ElasticSolve',  'Unknown element type.' )

     END SELECT

     U_Integ => IntegStuff % u
     V_Integ => IntegStuff % v
     W_Integ => IntegStuff % w
     S_Integ => IntegStuff % s
     N_Integ =  IntegStuff % n
!
!   Now we start integrating
!
    DO t=1,N_Integ

      u = U_Integ(t)
      v = V_Integ(t)
      w = W_Integ(t)

!------------------------------------------------------------------------------
!     Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
      stat = ElementInfo( Element,Nodes,u,v,w,SqrtElementMetric, &
                 Basis,dBasisdx,ddBasisddx,.FALSE. )

      IF( CoordinateSystem /= Cartesian ) THEN
         X = SUM( nodes % x(1:n)*Basis )
         Y = SUM( nodes % y(1:n)*Basis )
         Z = SUM( nodes % z(1:n)*Basis )
      END IF
      Radius = X

      CALL CoordinateSystemInfo( Metric, SqrtMetric, Symb, dSymb, X, Y, Z )

      s = 2.0D0*Pi*Radius*SqrtElementMetric * S_Integ(t)

!------------------------------------------------------------------------------
!  
!     Force at integration point
!   
      Force = 0.0D0
      DO i=1,dim
        Force(i) = SUM( LoadVector(i,1:n)*Basis )
      END DO
!
!     Lame parameters at the integration point
!
      Lame1 = SUM( NodalLame1(1:n)*Basis )
      Lame2 = SUM( NodalLame2(1:n)*Basis )
      Density = SUM( NodalDensity(1:n)*Basis )
      Damping = SUM( NodalDamping(1:n)*Basis )
!
!     Temperature at the integration point

      Temperature = SUM( NodalTemperature(1:n)*Basis )

!===========================================================================
!
!                       S T I F F N E S S   M A T R I X 
!
!                                    A N D
!
!                   R E S I D U A L   F O R C E   V E C T O R
!
!===========================================================================

!      Loop over the test functions:
!      -----------------------------
       DO p = 1,N
          DO i = 1,2
             Strain = 0.0d0
             Strain(i,1:2) = dBasisdx(p,1:2)
             IF (i.EQ.1) Strain(3,3) = Basis(p)/Radius
             Strain = 0.5d0*(Strain + TRANSPOSE(Strain))
             Stress = 2.0D0*Lame2*Strain + Lame1*TRACE(Strain,3)*Identity
             ForceVector(2*(p-1)+i) = ForceVector(2*(p-1)+i)+Basis(p)*Force(i)*s

!            Loop over the basis functions:
!            ------------------------------
             DO q = 1,N
                DO j = 1,2
                   Strain = 0.0d0
                   Strain(j,1:2) = dBasisdx(q,1:2)
                   IF (j.EQ.1) Strain(3,3) = Basis(q)/Radius
                   Strain = 0.5d0*(Strain + TRANSPOSE(Strain))
                   StiffMatrix(2*(p-1)+i,2*(q-1)+j) &
                        = StiffMatrix(2*(p-1)+i,2*(q-1)+j) &
                        + DDOT_PRODUCT(Strain,Stress,3)*s

                END DO
             END DO
          END DO
       END DO

!      Integrate mass matrix:
!      ----------------------
       DO p = 1,N
          DO q = 1,N
             DO i = 1,2
                MassMatrix(2*(p-1)+i,2*(q-1)+i) &
                        = MassMatrix(2*(p-1)+i,2*(q-1)+i) &
                        + Basis(p)*Basis(q)*Density*s

             END DO
          END DO
       END DO

!      Utilize the Rayleigh damping:
!      -----------------------------
       DampMatrix = Damping * MassMatrix

    END DO

!------------------------------------------------------------------------------

  END SUBROUTINE StressGeneralCompose
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   SUBROUTINE BackStressGeneralCompose( MassMatrix,DampMatrix,StiffMatrix, &
        ForceVector, LoadVector, NodalYoung, NodalPoisson, NodalDensity, &
        NodalDamping, PlaneStress,NodalHeatExpansion, NodalTemperature, &
        Element,n,Nodes, NodalDisplacement )
!DLLEXPORT StressGeneralCompose
!------------------------------------------------------------------------------
     REAL(KIND=dp) :: StiffMatrix(:,:),MassMatrix(:,:),DampMatrix(:,:), &
          NodalHeatExpansion(:,:,:)
     REAL(KIND=dp) :: NodalTemperature(:),Density,Damping,LoadVector(:,:)
     REAL(KIND=dp) :: NodalDisplacement(:,:)
     REAL(KIND=dp), DIMENSION(:) :: ForceVector,NodalPoisson,NodalYoung

     LOGICAL :: PlaneStress

     TYPE(Element_t) :: Element
     TYPE(Nodes_t) :: Nodes

     INTEGER :: n, Bound
!------------------------------------------------------------------------------
!
     REAL(KIND=dp) :: Basis(n),ddBasisddx(1,1,1)
     REAL(KIND=dp) :: dBasisdx(n,3),SqrtElementMetric

     REAL(KIND=dp) :: Force(3),NodalLame1(n),NodalLame2(n),NodalDensity(n), &
          NodalDamping(n),Lame1,Lame2
     REAL(KIND=dp) :: Grad(3,3),Identity(3,3),DetDefG,CofG(3,3),TrueForce(3)
     REAL(KIND=dp) ::  DefG(3,3), Strain(3,3), Stress2(3,3), Stress1(3,3)
     REAL(KIND=dp) :: dDefG(3,3),dStrain(3,3),dStress2(3,3),dStress1(3,3)
     REAL(KIND=dp) :: dDefGU(3,3),dStrainU(3,3),dStress2U(3,3),dStress1U(3,3)

     REAL(KIND=dp) :: Load(3),Temperature, Disp(3), GradBasis(3,3), GradTest(3,3)
     REAL(KIND=dp), DIMENSION(3,3) :: HeatExpansion

     REAL(KIND=dp) :: SqrtMetric, Metric(3,3), Symb(3,3,3), dSymb(3,3,3,3), Dfrm(3)

     INTEGER :: i,j,k,l,p,q,t,dim,i2,j2,k2,l2

     REAL(KIND=dp) :: s,u,v,w,X,Y,Z
  
     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff

     INTEGER :: N_Integ

     REAL(KIND=dp), DIMENSION(:), POINTER :: U_Integ,V_Integ,W_Integ,S_Integ

     LOGICAL :: stat, CylindricSymmetry
!------------------------------------------------------------------------------

     CylindricSymmetry = ( CoordinateSystem == CylindricSymmetric .OR. &
          CoordinateSystem == AxisSymmetric )

     IF ( CylindricSymmetry ) THEN
        dim = 3
     ELSE
        dim = CoordinateSystemDimension()
     END IF

     IF ( PlaneStress ) THEN
       NodalLame1(1:n) = NodalYoung * NodalPoisson /  &
            ( (1.0d0 - NodalPoisson**2) )
     ELSE
       NodalLame1(1:n) = NodalYoung * NodalPoisson /  &
          (  (1.0d0 + NodalPoisson) * (1.0d0 - 2.0d0*NodalPoisson) )
     END IF

     NodalLame2(1:n) = NodalYoung  / ( 2* (1.0d0 + NodalPoisson) )

     ForceVector = 0.0D0
     StiffMatrix = 0.0D0
     MassMatrix  = 0.0D0
     DampMatrix  = 0.0D0

     Identity = 0.0D0
     DO i = 1,dim
        Identity(i,i) = 1.0D0
     END DO
!    
!    Integration stuff
!    
     SELECT CASE(Element % TYPE % ElementCode/100)

!       Line segments:
!       --------------
        CASE( 2 )
        SELECT CASE( n )
           CASE( 2 )
           IntegStuff = GaussPoints( element,1 )
           CASE( 3 )
           IntegStuff = GaussPoints( element,4 )
           CASE( 4 )
           IntegStuff = GaussPoints( element,5 )
           CASE DEFAULT
           CALL Fatal( 'ElasticSolve',  'Unknown number of nodes.' )
        END SELECT

!       Triangles:
!       ----------
        CASE( 3 )
        SELECT CASE( n )
           CASE( 3 )
           IntegStuff = GaussPoints( element,1 )
           CASE( 6 )
           IntegStuff = GaussPoints( element,7 )
           CASE( 10 )
           IntegStuff = GaussPoints( element,17 )
           CASE DEFAULT
           CALL Fatal( 'ElasticSolve',  'Unknown number of nodes.' )
        END SELECT

!       Quadrilaterals:
!       ---------------
        CASE( 4 )
        SELECT CASE( n )
           CASE( 4 )
           IntegStuff = GaussPoints( element,4 )
           CASE( 8,9 )
           IntegStuff = GaussPoints( element,16 )
           CASE( 12,16 )
           IntegStuff = GaussPoints( element,25 )
           CASE DEFAULT
           CALL Fatal( 'ElasticSolve',  'Unknown number of nodes.' )
        END SELECT

!       Tetrahedrons:
!       -------------
        CASE( 5 )
        SELECT CASE( n )
           CASE( 4 )
           IntegStuff = GaussPoints( element,1 )
           CASE( 10 )
           IntegStuff = GaussPoints( element,11 )
           CASE DEFAULT
           CALL Fatal( 'ElasticSolve',  'Unknown number of nodes.' )
        END SELECT

!       Octahedrons:
!       ------------
        CASE( 8 )
        SELECT CASE( n )
           CASE( 8 )
           IntegStuff = GaussPoints( element,8 )
           CASE( 20,27 )
           IntegStuff = GaussPoints( element,64 )
           CASE DEFAULT
           CALL Fatal( 'ElasticSolve',  'Unknown number of nodes.' )
        END SELECT

!       Others:
!       -------
        CASE DEFAULT
           CALL Fatal( 'ElasticSolve',  'Unknown element type.' )

     END SELECT

     U_Integ => IntegStuff % u
     V_Integ => IntegStuff % v
     W_Integ => IntegStuff % w
     S_Integ => IntegStuff % s
     N_Integ =  IntegStuff % n
!
!   Now we start integrating
!
    DO t=1,N_Integ

      u = U_Integ(t)
      v = V_Integ(t)
      w = W_Integ(t)

!------------------------------------------------------------------------------
!     Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
      stat = ElementInfo( Element,Nodes,u,v,w,SqrtElementMetric, &
                 Basis,dBasisdx,ddBasisddx,.FALSE. )

!------------------------------------------------------------------------------
!     Coordinate system dependent info
!------------------------------------------------------------------------------
      IF ( CoordinateSystem /= Cartesian ) THEN
         X = SUM( nodes % x(1:n)*Basis )
         Y = SUM( nodes % y(1:n)*Basis )
         Z = SUM( nodes % z(1:n)*Basis )
      END IF

      CALL CoordinateSystemInfo( Metric, SqrtMetric, Symb, dSymb, X, Y, Z )

      s = SqrtMetric * SqrtElementMetric * S_Integ(t)

!------------------------------------------------------------------------------
!  
!     Force at integration point
!   
      Force = 0.0D0
      DO i=1,dim
        Force(i) = SUM( LoadVector(i,1:n)*Basis )
      END DO

!     Lame parameters at the integration point
!
      Lame1 = SUM( NodalLame1(1:n)*Basis )
      Lame2 = SUM( NodalLame2(1:n)*Basis )
      Density = SUM( NodalDensity(1:n)*Basis )
      Damping = SUM( NodalDamping(1:n)*Basis )
!
!     Temperature at the integration point
!
      Temperature = SUM( NodalTemperature(1:n)*Basis )
!
!     Heat expansion tensor values at the integration point
!
!      DO i=1,3
!        DO j=1,3
!          HeatExpansion(i,j) = SUM( NodalHeatExpansion(i,j,1:n)*Basis )
!        END DO
!      END DO

!===========================================================================
!
!                       S T I F F N E S S   M A T R I X 
!
!                                    A N D
!
!                   R E S I D U A L   F O R C E   V E C T O R
!
!===========================================================================

!      Covariant gradient of the current solution:
!      -------------------------------------------
       Metric(1,1) = 1.0D0/Metric(1,1)
       Metric(2,2) = 1.0D0/Metric(2,2)
       Metric(3,3) = 1.0D0/Metric(3,3)

       Grad = MATMUL(NodalDisplacement(:,1:N),dBasisdx)
       IF ( CoordinateSystem /= Cartesian ) THEN
!         Contravariant components of the displacement:
          Disp = MATMUL(NodalDisplacement(:,1:N),Basis)
!         Account for the Christoffel symbols:
          DO i = 1,dim
             DO j = 1,dim
                DO k = 1,dim
                   Grad(i,j) = Grad(i,j) + Symb(j,k,i) * Disp(k)
                END DO
             END DO
          END DO
       END IF

!      Deformation gradient
!      --------------------
       DefG = Identity + Grad
       dDefG = Grad
       DetDefG = 1.0D0

!      Covariant components of the strain tensor:
!      ------------------------------------------
       Strain = 0.0D0
       DO i = 1,dim
          DO j = i,dim
             DO k = 1,dim
                Strain(i,j) = Strain(i,j) + Metric(i,k)*Grad(k,j)
                DO l = 1,dim
                   Strain(i,j) = Strain(i,j) + Metric(k,l)*Grad(k,i)*Grad(l,j)/2.0D0
                END DO
             END DO
          END DO
       END DO
       Strain = (Strain + TRANSPOSE(Strain))/2.0D0

       Stress2 = 2.0D0*Lame2*Strain + Lame1*TRACE(Strain,dim)*Identity
       Stress1 = MATMUL( DefG, Stress2 )

       DetDefG = 1.0d0

!       SELECT CASE( dim )
!          CASE( 1 )
!          DetDefG = DefG(1,1)
!          CASE( 2 )
!          DetDefG = DefG(1,1)*DefG(2,2) - DefG(1,2)*DefG(2,1)
!          CASE( 3 )
!          DetDefG = DefG(1,1) * ( DefG(2,2)*DefG(3,3) - DefG(2,3)*DefG(3,2) ) + &
!                    DefG(1,2) * ( DefG(2,3)*DefG(3,1) - DefG(2,1)*DefG(3,3) ) + &
!                    DefG(1,3) * ( DefG(2,1)*DefG(3,2) - DefG(2,2)*DefG(3,1) )
!       END SELECT

!      Gateaux derivatives of the deformation gradient, stress
!      and strain, with respect to the current displacement:
!      -------------------------------------------------------
       dStrainU = 0.0D0
       DO i = 1,dim
          DO j = 1,dim
             DO k = 1,dim
                DO l = 1,dim
                   dStrainU(i,j) = dStrain(i,j) + Metric(k,l)*Grad(k,i)*Grad(l,j)/2.0D0
                END DO
             END DO
          END DO
       END DO

       dStress2U = 2.0D0*Lame2*dStrainU + Lame1*TRACE(dStrainU,dim)*Identity
       dStress1U = MATMUL(dDefGU,Stress2) + MATMUL(DefG,dStress2U)

       IF ( CoordinateSystem == AxisSymmetric ) THEN
          Bound = 2
       ELSE
          Bound = dim
       END IF

!      Loop over the test funtions:
!      ----------------------------
       DO p = 1,N
          DO i = 1,Bound

!            Gateaux derivatives of the solution with respect to the test functions:
!            -----------------------------------------------------------------------
             GradTest = 0.0D0
             GradTest(i,:) = dBasisdx(p,:)
             IF ( CoordinateSystem /= Cartesian ) THEN
                Disp = 0.0D0; Disp(i) = Basis(p)
                DO i2 = 1,dim
                   DO j2 = 1,dim
                      DO k2 = 1,dim
                         GradTest(i2,j2) = GradTest(i2,j2) - Symb(i2,j2,k2) * Disp(k2)
                      END DO
                   END DO
                END DO
             END IF

             dStrain = 0.0D0
             DO i2 = 1,dim
                DO j2 = i,dim
                   DO k2 = 1,dim
                      dStrain(i2,j2) = dStrain(i2,j2) &
                           + ( Metric(i2,k2)*GradTest(k2,j2) &
                           +   Metric(j2,k2)*GradTest(k2,i2) )/2.0D0
                      DO l2 = 1,dim
                         dStrain(i2,j2) = dStrain(i2,j2) &
                              + Metric(k2,l2)*GradTest(k2,i2)*GradTest(l2,j2)/2.0D0
                      END DO
                   END DO
                END DO
             END DO

             dDefG = GradTest
!             dStrain = (MATMUL(TRANSPOSE(DefG),dDefG) &
!                  + MATMUL(TRANSPOSE(dDefG),DefG))/2.0D0

             dStress2 = 2.0D0*Lame2*dStrain + Lame1*TRACE(dStrain,dim)*Identity
             dStress1 = MATMUL(dDefG,Stress2) + MATMUL(DefG,dStress2)

             ForceVector(Bound*(p-1)+i) = ForceVector(Bound*(p-1)+i) &
                  +(Basis(p)*Force(i)*DetDefG &
                   -DDOT_PRODUCT( Stress1 , dDefG, 3) &
                   +DDOT_PRODUCT(dStress1U, dDefG, 3) )*s

!            Loop over the basis functions:
!            ------------------------------
             DO q = 1,N
                DO j = 1,Bound

!                  Contravariant components of the test function:
!                  ----------------------------------------------
                   GradBasis = 0.0D0; GradBasis(j,:) = dBasisdx(q,:)
                   
!                  Covariant derivatives:
!                  ----------------------
                   IF ( CoordinateSystem /= Cartesian ) THEN
                      Disp = 0.0D0; Disp(j) = Basis(q)
                      DO i2 = 1,dim
                         DO j2 = 1,dim
                            DO k2 = 1,dim
                               GradBasis(i2,j2) = GradBasis(i2,j2) + Symb(j2,k2,i2) * Disp(k2)
                            END DO
                         END DO
                      END DO
                   END IF

                   MassMatrix(Bound*(p-1)+i,Bound*(q-1)+j) &
                        = MassMatrix(Bound*(p-1)+i,Bound*(q-1)+j) &
                        + Basis(p)*Basis(q)*Density*DetDefG*s

                   StiffMatrix(Bound*(p-1)+i,Bound*(q-1)+j) &
                        = StiffMatrix(Bound*(p-1)+i,Bound*(q-1)+j) &
                        + DDOT_PRODUCT(dStress1,GradBasis,3)*s

                END DO
             END DO
          END DO
       END DO

!      Rayleigh damping:
!      -----------------
       DampMatrix = Damping * MassMatrix

    END DO

!------------------------------------------------------------------------------

  END SUBROUTINE BackStressGeneralCompose
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
 SUBROUTINE StressBoundary( BoundaryMatrix,BoundaryVector,LoadVector, &
   NodalAlpha,NodalBeta,NodalDisplacement,Element,n,Nodes, &
     Parent,pn,ParentNodes,Flow,fn,FlowNodes,Velocity,Pressure,NodalViscosity, &
     NodalDensity, CompressibilityDefined )
!DLLEXPORT StressBoundary
   USE Integration
   USE LinearAlgebra
!------------------------------------------------------------------------------
   REAL(KIND=dp) :: BoundaryMatrix(:,:),BoundaryVector(:),NodalDisplacement(:,:)
   REAL(KIND=dp) :: NodalAlpha(:,:),NodalBeta(:),LoadVector(:,:),Pressure(:), &
                    Velocity(:,:),NodalViscosity(:), NodalDensity(:)
   TYPE(Element_t),POINTER  :: Element,Parent,Flow
   TYPE(Nodes_t)    :: Nodes,ParentNodes,FlowNodes
   INTEGER :: n,pn,fn
   LOGICAL :: CompressibilityDefined
!------------------------------------------------------------------------------
   REAL(KIND=dp) :: Basis(n),ddBasisddx(1,1,1)
   REAL(KIND=dp) :: dBasisdx(n,3),SqrtElementMetric
   REAL(KIND=dp) :: x(n),y(n),z(n), Density

   REAL(KIND=dp) :: PBasis(pn)
   REAL(KIND=dp) :: PdBasisdx(pn,3),PSqrtElementMetric

   REAL(KIND=dp) :: FBasis(fn)
   REAL(KIND=dp) :: FdBasisdx(fn,3),FSqrtElementMetric

   REAL(KIND=dp) :: u,v,w,s,ParentU,ParentV,ParentW
   REAL(KIND=dp) :: FlowStress(3,3),Viscosity
   REAL(KIND=dp) :: Force(3),Alpha(3),Beta,Normal(3),Identity(3,3)
   REAL(KIND=dp) :: Grad(3,3),DefG(3,3),DetDefG,CofG(3,3),ScaleFactor
   REAL(KIND=dp), POINTER :: U_Integ(:),V_Integ(:),W_Integ(:),S_Integ(:)

   INTEGER :: i,j,t,q,p,dim,N_Integ

   LOGICAL :: stat,pstat

   TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff

!------------------------------------------------------------------------------

   dim = CoordinateSystemDimension()

   Identity = 0.0D0
   DO i = 1,dim
      Identity(i,i) = 1.0D0
   END DO

   BoundaryVector = 0.0D0
   BoundaryMatrix = 0.0D0
!
!  Integration stuff
!
   IntegStuff = GaussPoints( element, element % TYPE % GaussPoints )
   U_Integ => IntegStuff % u
   V_Integ => IntegStuff % v
   W_Integ => IntegStuff % w
   S_Integ => IntegStuff % s
   N_Integ =  IntegStuff % n
!
!  Now we start integrating
!
   DO t=1,N_Integ

      u = U_Integ(t)
      v = V_Integ(t)
      w = W_Integ(t)

!------------------------------------------------------------------------------
!     Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
      stat = ElementInfo( Element,Nodes,u,v,w,SqrtElementMetric, &
                 Basis,dBasisdx,ddBasisddx,.FALSE. )

      s = SqrtElementMetric * S_Integ(t)

!     Calculate the basis functions for the parent element:
!     -----------------------------------------------------
      DO i = 1,n
         DO j = 1,pn
            IF( Element % NodeIndexes(i) == Parent % NodeIndexes(j) ) THEN
               x(i) = Parent % TYPE % NodeU(j)
               y(i) = Parent % TYPE % NodeV(j)
               z(i) = Parent % TYPE % NodeW(j)
               EXIT
            END IF
         END DO
      END DO
      ParentU = SUM( Basis(1:n)*x(1:n) )
      ParentV = SUM( Basis(1:n)*y(1:n) )
      ParentW = SUM( Basis(1:n)*z(1:n) )

      Pstat= ElementInfo( Parent,ParentNodes,ParentU,ParentV,ParentW, &
           PSqrtElementMetric,PBasis,PdBasisdx,ddBasisddx,.FALSE. )

!     Computes the cofactor matrix of the deformation gradient:
!     ---------------------------------------------------------
      Grad = MATMUL(NodalDisplacement(:,1:pn),PdBasisdx)
      DefG = Identity + Grad 
      SELECT CASE( dim )
         CASE(1)
            DetDefG = DefG(1,1)
         CASE(2)
            DetDefG = DefG(1,1)*DefG(2,2) - DefG(1,2)*DefG(2,1)
         CASE(3)
            DetDefG = DefG(1,1) * ( DefG(2,2)*DefG(3,3) - DefG(2,3)*DefG(3,2) ) + &
                      DefG(1,2) * ( DefG(2,3)*DefG(3,1) - DefG(2,1)*DefG(3,3) ) + &
                      DefG(1,3) * ( DefG(2,1)*DefG(3,2) - DefG(2,2)*DefG(3,1) )
      END SELECT
      CALL InvertMatrix( DefG, dim )     ! Inverse of the deformation gradient
      DefG = DetDefG*TRANSPOSE( DefG )   ! Cofactor of the deformation gradient

!     Calculate traction from the flow solution:
!     ------------------------------------------
      IF ( ASSOCIATED( Flow ) ) THEN
        DO i = 1,n
          DO j = 1,fn
            IF ( Element % NodeIndexes(i) == Flow % NodeIndexes(j) ) THEN
              x(i) = Flow % TYPE % NodeU(j)
              y(i) = Flow % TYPE % NodeV(j)
              z(i) = Flow % TYPE % NodeW(j)
              EXIT
            END IF
          END DO
        END DO

        ParentU = SUM( Basis(1:n)*x(1:n) )
        ParentV = SUM( Basis(1:n)*y(1:n) )
        ParentW = SUM( Basis(1:n)*z(1:n) )

        Pstat = ElementInfo( Flow,FlowNodes,ParentU,ParentV,ParentW, &
          FSqrtElementMetric,FBasis,FdBasisdx,ddBasisddx,.FALSE. )

        Grad = MATMUL( Velocity(:,1:fn),FdBasisdx )
        Density    = SUM( NodalDensity(1:fn) * FBasis )
        Viscosity  = SUM( NodalViscosity(1:fn) * FBasis )

        Viscosity = EffectiveViscosity( Viscosity,Density,Velocity(1,:),Velocity(2,:), &
             Velocity(3,:),FlowElement,FlowNodes,fn,fn,ParentU,ParentV,ParentW)
        Viscosity  = SUM( NodalViscosity(1:fn) * FBasis )
 
        FlowStress = Viscosity * ( Grad + TRANSPOSE(Grad) )

        DO i=1,dim
          FlowStress(i,i) = FlowStress(i,i) - SUM( Pressure(1:fn)*FBasis )
          IF( CompressibilityDefined ) THEN
             FlowStress(i,i) = FlowStress(i,i) - Viscosity * (2.0d0/3.0d0)*TRACE(Grad,dim)
          END IF
        END DO

      END IF

!------------------------------------------------------------------------------
!     The following four lines scale the vectors of the cofactor matrix to unit
!     vectors. These lines are only for testing and should be commented out in
!     the final code.
!     -------------------------------------------------------------------------
!       ScaleFactor = ( DefG(1,1)**2.0D0 + DefG(2,1)**2.0D0 )**0.5
!       DefG(:,1) = DefG(:,1)/ScaleFactor
!       ScaleFactor = ( DefG(1,2)**2.0D0 + DefG(2,2)**2.0D0 )**0.5
!       DefG(:,2) = DefG(:,2)/ScaleFactor
!------------------------------------------------------------------------------

      Force = 0.0D0
      DO i=1,dim
        Force(i) = SUM( LoadVector(i,1:n)*Basis )
        Alpha(i) = SUM( NodalAlpha(i,1:n)*Basis )
      END DO

!     Normal vector and its transformation:
!     --------------------------------------
      Normal = NormalVector( Element,Nodes,u,v,.TRUE. )
      Normal = MATMUL(DefG,Normal)

      IF ( ASSOCIATED( Flow ) ) THEN
        Force = Force + MATMUL( FlowStress, Normal )
      END IF
      Force = Force + SUM( NodalBeta(1:n)*Basis ) * Normal

      DO p=1,N
        DO q=1,N
          DO i=1,dim
            BoundaryMatrix((p-1)*dim+i,(q-1)*dim+i) =  &
              BoundaryMatrix((p-1)*dim+i,(q-1)*dim+i) + &
                 s * Alpha(i) * Basis(q) * Basis(p)
            END DO
         END DO
     END DO
     
     DO q=1,N
        DO i=1,dim
          BoundaryVector((q-1)*dim+i) = BoundaryVector((q-1)*dim+i) + &
               s * Basis(q) * Force(i)
        END DO
     END DO
     
  END DO

!------------------------------------------------------------------------------
 END SUBROUTINE StressBoundary
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
 SUBROUTINE StressGeneralBoundary( BoundaryMatrix,BoundaryVector,LoadVector, &
   NodalAlpha,NodalBeta,NodalDisplacement,Element,n,Nodes, &
     Parent,pn,ParentNodes,Flow,fn,FlowNodes,Velocity,Pressure,NodalViscosity, &
     NodalDensity, CompressibilityDefined )
!DLLEXPORT StressGeneralBoundary
!------------------------------------------------------------------------------
   REAL(KIND=dp) :: BoundaryMatrix(:,:),BoundaryVector(:),NodalDisplacement(:,:)
   REAL(KIND=dp) :: NodalAlpha(:,:),NodalBeta(:),LoadVector(:,:),Pressure(:), &
                    Velocity(:,:),NodalViscosity(:), NodalDensity(:)
   TYPE(Element_t),POINTER  :: Element,Parent,Flow
   TYPE(Nodes_t)    :: Nodes,ParentNodes,FlowNodes
   INTEGER :: n,pn,fn
   LOGICAL :: CompressibilityDefined
!------------------------------------------------------------------------------
   REAL(KIND=dp) :: Basis(n),ddBasisddx(1,1,1)
   REAL(KIND=dp) :: dBasisdx(n,3),SqrtElementMetric
   REAL(KIND=dp) :: x(n),y(n),z(n), Density

   REAL(KIND=dp) :: PBasis(pn)
   REAL(KIND=dp) :: PdBasisdx(pn,3),PSqrtElementMetric

   REAL(KIND=dp) :: FBasis(fn)
   REAL(KIND=dp) :: FdBasisdx(fn,3),FSqrtElementMetric

   REAL(KIND=dp) :: u,v,w,s,ParentU,ParentV,ParentW
   REAL(KIND=dp) :: FlowStress(3,3),Viscosity
   REAL(KIND=dp) :: Force(3),Alpha(3),Beta,Normal(3),Identity(3,3)
   REAL(KIND=dp) :: Grad(3,3),DefG(3,3),DetDefG,CofG(3,3),ScaleFactor
   REAL(KIND=dp), POINTER :: U_Integ(:),V_Integ(:),W_Integ(:),S_Integ(:)

   INTEGER :: i,j,t,q,p,dim,N_Integ

   LOGICAL :: stat,pstat

   TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff

   REAL(KIND=dp) :: SqrtMetric,Metric(3,3),Symb(3,3,3),dSymb(3,3,3,3),xx,yy,zz
!------------------------------------------------------------------------------

   dim = Element % TYPE % DIMENSION + 1

   BoundaryVector = 0.0D0
   BoundaryMatrix = 0.0D0
!
!  Integration stuff
!
   IntegStuff = GaussPoints( element )
   U_Integ => IntegStuff % u
   V_Integ => IntegStuff % v
   W_Integ => IntegStuff % w
   S_Integ => IntegStuff % s
   N_Integ =  IntegStuff % n
!
!  Now we start integrating
!
   DO t=1,N_Integ

     u = U_Integ(t)
     v = V_Integ(t)
     w = W_Integ(t)

!------------------------------------------------------------------------------
!     Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
      stat = ElementInfo( Element,Nodes,u,v,w,SqrtElementMetric, &
                 Basis,dBasisdx,ddBasisddx,.FALSE. )

!------------------------------------------------------------------------------
!
!    CoordinateSystemystem dependent info
!
     IF ( CoordinateSystem /= Cartesian ) THEN
       XX = SUM( nodes % x(1:n)*Basis )
       YY = SUM( nodes % y(1:n)*Basis )
       ZZ = SUM( nodes % z(1:n)*Basis )
     END IF

     CALL CoordinateSystemInfo( Metric,SqrtMetric,Symb,dSymb,XX,YY,ZZ )
!
     s = 2.0d0 * Pi * SqrtMetric * SqrtElementMetric * S_Integ(t)

!     Calculate the basis functions for the parent element:
!     -----------------------------------------------------
      DO i = 1,n
         DO j = 1,pn
            IF( Element % NodeIndexes(i) == Parent % NodeIndexes(j) ) THEN
               x(i) = Parent % TYPE % NodeU(j)
               y(i) = Parent % TYPE % NodeV(j)
               z(i) = Parent % TYPE % NodeW(j)
               EXIT
            END IF
         END DO
      END DO

      ParentU = SUM( Basis(1:n)*x(1:n) )
      ParentV = SUM( Basis(1:n)*y(1:n) )
      ParentW = SUM( Basis(1:n)*z(1:n) )

      Pstat= ElementInfo( Parent,ParentNodes,ParentU,ParentV,ParentW, &
           PSqrtElementMetric,PBasis,PdBasisdx,ddBasisddx,.FALSE. )

!     Calculate traction from the flow solution:
!     ------------------------------------------
      IF ( ASSOCIATED( Flow ) ) THEN
        DO i = 1,n
          DO j = 1,fn
            IF ( Element % NodeIndexes(i) == Flow % NodeIndexes(j) ) THEN
              x(i) = Flow % TYPE % NodeU(j)
              y(i) = Flow % TYPE % NodeV(j)
              z(i) = Flow % TYPE % NodeW(j)
              EXIT
            END IF
          END DO
        END DO

        ParentU = SUM( Basis(1:n)*x(1:n) )
        ParentV = SUM( Basis(1:n)*y(1:n) )
        ParentW = SUM( Basis(1:n)*z(1:n) )

        Pstat = ElementInfo( Flow,FlowNodes,ParentU,ParentV,ParentW, &
          FSqrtElementMetric,FBasis,FdBasisdx,ddBasisddx,.FALSE. )

        Grad = MATMUL( Velocity(:,1:fn),FdBasisdx )
        Density    = SUM( NodalDensity(1:fn) * FBasis )
        Viscosity  = SUM( NodalViscosity(1:fn) * FBasis )

        Viscosity = EffectiveViscosity( Viscosity,Density,Velocity(1,:),Velocity(2,:), &
             Velocity(3,:),FlowElement,FlowNodes,fn,fn,ParentU,ParentV,ParentW)
 
        FlowStress = Viscosity * ( Grad + TRANSPOSE(Grad) )

        DO i=1,dim
          FlowStress(i,i) = FlowStress(i,i) - SUM( Pressure(1:fn)*FBasis )
          IF( CompressibilityDefined ) THEN
             FlowStress(i,i) = FlowStress(i,i) - Viscosity * (2.0d0/3.0d0)*TRACE(Grad,dim)
          END IF
        END DO
      END IF

      Force = 0.0D0
      Alpha = 0.0D0
      DO i=1,dim
        Force(i) = SUM( LoadVector(i,1:n)*Basis )
        Alpha(i) = SUM( NodalAlpha(i,1:n)*Basis )
      END DO

!     Normal vector and its transformation:
!     --------------------------------------
      Normal = NormalVector( Element,Nodes,u,v,.TRUE. )
!     Normal = MATMUL(DefG,Normal)

      IF ( ASSOCIATED( Flow ) ) THEN
         Force = Force + MATMUL( FlowStress, Normal )
      END IF

!------------------------------------------------------------------------------
!    Add to load: given force in normal direction
!------------------------------------------------------------------------------
!
     Beta  = SUM( NodalBeta(1:n)*Basis )
     DO i=1,dim
       DO j=1,dim
         Force(i) = Force(i) + Beta*Metric(i,j)*Normal(j)
       END DO
     END DO
!------------------------------------------------------------------------------
!
     DO p=1,N
       DO q=1,N
         DO i=1,dim
           BoundaryMatrix((p-1)*dim+i,(q-1)*dim+i) =  &
               BoundaryMatrix((p-1)*dim+i,(q-1)*dim+i) + &
                  s * Alpha(i) * Basis(q) * Basis(p)
         END DO
       END DO
     END DO

     DO q=1,N
       DO i=1,dim
         BoundaryVector((q-1)*dim+i) = BoundaryVector((q-1)*dim+i) + &
                      s * Basis(q) * Force(i)
       END DO
     END DO

   END DO
!------------------------------------------------------------------------------
 END SUBROUTINE StressGeneralBoundary
!------------------------------------------------------------------------------




!------------------------------------------------------------------------------
 FUNCTION TRACE(A,N) RESULT(B)
!------------------------------------------------------------------------------
   IMPLICIT NONE
   DOUBLE PRECISION :: A(:,:),B
   INTEGER :: N
!------------------------------------------------------------------------------
   INTEGER :: I
!------------------------------------------------------------------------------
   B = 0.0D0
   DO i = 1,N
      B = B + A(i,i)
   END DO
!------------------------------------------------------------------------------
 END FUNCTION TRACE
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
 FUNCTION DDOT_PRODUCT(A,B,N) RESULT(C)
!------------------------------------------------------------------------------
   IMPLICIT NONE
   DOUBLE PRECISION :: A(:,:),B(:,:),C
   INTEGER :: N
!------------------------------------------------------------------------------
   INTEGER :: I,J
!------------------------------------------------------------------------------
   C = 0.0D0
   DO I = 1,N
      DO J = 1,N
         C = C + A(I,J)*B(I,J)
      END DO
   END DO
!------------------------------------------------------------------------------
 END FUNCTION DDOT_PRODUCT
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  END SUBROUTINE ElasticSolver
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   FUNCTION ElastBoundaryResidual( Model, Edge, Mesh, Quant, Perm, Gnorm ) RESULT( Indicator )
!------------------------------------------------------------------------------
     USE Integration
     USE ElementDescription
     IMPLICIT NONE
!------------------------------------------------------------------------------
     TYPE(Model_t) :: Model
     INTEGER :: Perm(:)
     REAL(KIND=dp) :: Quant(:), Indicator(2), Gnorm
     TYPE( Mesh_t ), POINTER    :: Mesh
     TYPE( Element_t ), POINTER :: Edge
!------------------------------------------------------------------------------

     TYPE(Nodes_t) :: Nodes, EdgeNodes
     TYPE(Element_t), POINTER :: Element, Bndry

     INTEGER :: i,j,k,n,l,t,dim,DOFs,Pn,En
     LOGICAL :: stat, GotIt

     REAL(KIND=dp) :: SqrtMetric, Metric(3,3), Symb(3,3,3), dSymb(3,3,3,3)

     REAL(KIND=dp) :: Normal(3), EdgeLength, x(4), y(4), z(4), ExtPressure(MAX_NODES)

     REAL(KIND=dp) :: u, v, w, s, detJ, EdgeBasis(4), dEdgeBasisdx(4,3), &
         Basis(MAX_NODES),dBasisdx(MAX_NODES,3), ddBasisddx(MAX_NODES,3,3)

     REAL(KIND=dp) :: Residual(3), ResidualNorm, Area
     REAL(KIND=dp) :: Force(3,MAX_NODES)
     REAL(KIND=dp) :: Dir(3)

     REAL(KIND=dp) :: Displacement(3), NodalDisplacement(3,MAX_NODES)
     REAL(KIND=dp) :: YoungsModulus, NodalYoungsModulus(MAX_NODES)
     REAL(KIND=dp) :: PoissonRatio, NodalPoissonRatio(MAX_NODES)
     REAL(KIND=dp) :: Density, NodalDensity(MAX_NODES)
     REAL(KIND=dp) :: Temperature, NodalTemperature(MAX_NODES)
     REAL(KIND=dp) :: Lame1, NodalLame1(MAX_NODES)
     REAL(KIND=dp) :: Lame2, NodalLame2(MAX_NODES)
     REAL(KIND=dp) :: Damping, NodalDamping(MAX_NODES)
     REAL(KIND=dp) :: HeatExpansionCoeff, NodalHeatExpansionCoeff(MAX_NODES)
     REAL(KIND=dp) :: ReferenceTemperature, NodalReferenceTemperature(MAX_NODES)
     REAL(KIND=dp) :: Grad(3,3), DefG(3,3), Strain(3,3), Stress1(3,3), Stress2(3,3)
     REAL(KIND=dp) :: Identity(3,3), YoungsAverage

     LOGICAL :: PlaneStress

     INTEGER :: eq_id

     TYPE(ValueList_t), POINTER :: Material

     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff
!------------------------------------------------------------------------------

!    Initialize:
!    -----------
     Indicator = 0.0d0
     Gnorm = 0.0d0

     Identity = 0.0d0
     DO i=1,3
        Identity(i,i) = 1.0d0
     END DO

     Metric = 0.0d0
     DO i=1,3
        Metric(i,i) = 1.0d0
     END DO

     SELECT CASE( CurrentCoordinateSystem() )
        CASE( AxisSymmetric, CylindricSymmetric )
           dim = 3
        CASE DEFAULT
           dim = CoordinateSystemDimension()
     END SELECT

     DOFs = dim
     IF ( CurrentCoordinateSystem() == AxisSymmetric ) DOFs = DOFs-1
!    
!    --------------------------------------------------
     Element => Edge % BoundaryInfo % Left

     IF ( .NOT. ASSOCIATED( Element ) ) THEN

        Element => Edge % BoundaryInfo % Right

     ELSE IF ( ANY( Perm( Element % NodeIndexes ) <= 0 ) ) THEN

        Element => Edge % BoundaryInfo % Right

     END IF

     IF ( .NOT. ASSOCIATED( Element ) ) RETURN
     IF ( ANY( Perm( Element % NodeIndexes ) <= 0 ) ) RETURN

     En = Edge % TYPE % NumberOfNodes
     Pn = Element % TYPE % NumberOfNodes

     ALLOCATE( EdgeNodes % x(En), EdgeNodes % y(En), EdgeNodes % z(En) )

     EdgeNodes % x = Mesh % Nodes % x(Edge % NodeIndexes)
     EdgeNodes % y = Mesh % Nodes % y(Edge % NodeIndexes)
     EdgeNodes % z = Mesh % Nodes % z(Edge % NodeIndexes)

     ALLOCATE( Nodes % x(Pn), Nodes % y(Pn), Nodes % z(Pn) )

     Nodes % x = Mesh % Nodes % x(Element % NodeIndexes)
     Nodes % y = Mesh % Nodes % y(Element % NodeIndexes)
     Nodes % z = Mesh % Nodes % z(Element % NodeIndexes)

     DO l = 1,En
       DO k = 1,Pn
          IF ( Edge % NodeIndexes(l) == Element % NodeIndexes(k) ) THEN
             x(l) = Element % TYPE % NodeU(k)
             y(l) = Element % TYPE % NodeV(k)
             z(l) = Element % TYPE % NodeW(k)
             EXIT
          END IF
       END DO
     END DO
!
!    Integrate square of residual over boundary element:
!    ---------------------------------------------------
     Indicator     = 0.0d0
     EdgeLength    = 0.0d0
     YoungsAverage = 0.0d0
     ResidualNorm  = 0.0d0

     DO j=1,Model % NumberOfBCs
        IF ( Edge % BoundaryInfo % Constraint /= Model % BCs(j) % Tag ) CYCLE

!        IF ( .NOT. ListGetLogical( Model % BCs(j) % Values, &
!                  'Flow Force BC', gotIt ) ) CYCLE

!
!       Logical parameters:
!       -------------------
        eq_id = ListGetInteger( Model % Bodies(Element % BodyId) % Values, 'Equation', &
             minv=1, maxv=Model % NumberOfEquations )
        PlaneStress = ListGetLogical( Model % Equations(eq_id) % Values,'Plane Stress',GotIt )
!
!       Material parameters:
!       --------------------
        k = ListGetInteger( Model % Bodies(Element % BodyId) % Values, 'Material', &
                minv=1, maxv=Model % NumberOFMaterials )
        Material => Model % Materials(k) % Values
        NodalYoungsModulus(1:En) = ListGetReal( Material,'Youngs Modulus', &
             En, Edge % NodeIndexes, GotIt )
        NodalPoissonRatio(1:En) = ListGetReal( Material, 'Poisson Ratio', &
             En, Edge % NodeIndexes, GotIt )
        NodalTemperature(1:En) = ListGetReal( Material,'Temperature', &
             En, Edge % NodeIndexes, GotIt )
        NodalReferenceTemperature(1:En) = ListGetReal( Material,'Reference Temperature', &
             En, Edge % NodeIndexes, GotIt )
        NodalDensity(1:En) = ListGetReal( Material,'Density',En,Edge % NodeIndexes, GotIt )
        NodalDamping(1:En) = ListGetReal( Material,'Damping',En,Edge % NodeIndexes, GotIt )
        HeatExpansionCoeff   = 0.0D0
        
        IF ( PlaneStress ) THEN
           NodalLame1(1:En) = NodalYoungsModulus(1:En) * NodalPoissonRatio(1:En) /  &
                ( (1.0d0 - NodalPoissonRatio(1:En)**2) )
        ELSE
           NodalLame1(1:En) = NodalYoungsModulus(1:En) * NodalPoissonRatio(1:En) /  &
                (  (1.0d0 + NodalPoissonRatio(1:En)) * ( 1.0d0 - 2.0d0*NodalPoissonRatio(1:En) ) )
        END IF

        NodalLame2(1:En) = NodalYoungsModulus(1:En)  / ( 2.0d0*(1.0d0 + NodalPoissonRatio(1:En) ) )
!
!       Given traction:
!       ---------------
        Force = 0.0d0

        Force(1,1:En) = ListGetReal( Model % BCs(j) % Values, &
            'Force 1', En, Edge % NodeIndexes, GotIt )

        Force(2,1:En) = ListGetReal( Model % BCs(j) % Values, &
            'Force 2', En, Edge % NodeIndexes, GotIt )

        Force(3,1:En) = ListGetReal( Model % BCs(j) % Values, &
            'Force 3', En, Edge % NodeIndexes, GotIt )

!       Force in normal direction:
!       ---------------------------
        ExtPressure(1:En) = ListGetReal( Model % BCs(j) % Values, &
          'Normal Force', En, Edge % NodeIndexes, GotIt )

!       If dirichlet BC for displacement in any direction given,
!       nullify force in that directon:
!       ------------------------------------------------------------------
        Dir = 1.0d0
        s = ListGetConstReal( Model % BCs(j) % Values, 'Displacement 1', GotIt )
        IF ( GotIt ) Dir(1) = 0

        s = ListGetConstReal( Model % BCs(j) % Values, 'Displacement 2', GotIt )
        IF ( GotIt ) Dir(2) = 0

        s = ListGetConstReal( Model % BCs(j) % Values, 'Displacement 3', GotIt )
        IF ( GotIt ) Dir(3) = 0
!
!       Elementwise nodal solution:
!       ---------------------------
        NodalDisplacement = 0.0d0
        DO k=1,DOFs
           NodalDisplacement(k,1:Pn) = Quant( DOFs*Perm(Element % NodeIndexes)-DOFs+k )
        END DO
!
!       Integration:
!       ------------
        EdgeLength    = 0.0d0
        YoungsAverage = 0.0d0
        ResidualNorm  = 0.0d0

        IntegStuff = GaussPoints( Edge )

        DO t=1,IntegStuff % n
           u = IntegStuff % u(t)
           v = IntegStuff % v(t)
           w = IntegStuff % w(t)

           stat = ElementInfo( Edge, EdgeNodes, u, v, w, detJ, &
               EdgeBasis, dEdgeBasisdx, ddBasisddx, .FALSE., .FALSE. )

           IF ( CurrentCoordinateSystem() == Cartesian ) THEN
              s = IntegStuff % s(t) * detJ
           ELSE
              u = SUM( EdgeBasis(1:En) * EdgeNodes % x(1:En) )
              v = SUM( EdgeBasis(1:En) * EdgeNodes % y(1:En) )
              w = SUM( EdgeBasis(1:En) * EdgeNodes % z(1:En) )
      
              CALL CoordinateSystemInfo( Metric, SqrtMetric, &
                          Symb, dSymb, u, v, w )

              s = IntegStuff % s(t) * detJ * SqrtMetric
           END IF

           Normal = NormalVector( Edge, EdgeNodes, u, v, .TRUE. )

           u = SUM( EdgeBasis(1:En) * x(1:En) )
           v = SUM( EdgeBasis(1:En) * y(1:En) )
           w = SUM( EdgeBasis(1:En) * z(1:En) )

           stat = ElementInfo( Element, Nodes, u, v, w, detJ, &
              Basis, dBasisdx, ddBasisddx, .FALSE., .FALSE. )

           Lame1 = SUM( NodalLame1(1:En) * EdgeBasis(1:En) )
           Lame2 = SUM( NodalLame2(1:En) * EdgeBasis(1:En) )
!
!          Stress tensor on the edge:
!          --------------------------
           Grad = MATMUL( NodalDisplacement(:,1:Pn),dBasisdx(1:Pn,:) )
           DefG = Identity + Grad
           Strain = (TRANSPOSE(Grad)+Grad+MATMUL(TRANSPOSE(Grad),Grad))/2.0D0
           Stress2 = 2.0D0*Lame2*Strain + Lame1*TRACE(Strain,dim)*Identity
           Stress1 = MATMUL(DefG,Stress2)
!
!          Given force at the integration point:
!          -------------------------------------
           Residual = 0.0d0
           Residual = MATMUL( Force(:,1:En), EdgeBasis(1:En) ) - &
                 SUM( ExtPressure(1:En) * EdgeBasis(1:En) ) * Normal

           Residual = Residual - MATMUL( Stress1, Normal ) * Dir

           EdgeLength   = EdgeLength + s
           ResidualNorm = ResidualNorm + s * SUM( Residual(1:dim) ** 2 )
           YoungsAverage = YoungsAverage + &
                   s * SUM( NodalYoungsModulus(1:En) * EdgeBasis(1:En) )
        END DO
        EXIT
     END DO

     IF ( YoungsAverage > AEPS ) THEN
        YoungsAverage = YoungsAverage / EdgeLength
        Indicator = EdgeLength * ResidualNorm / YoungsAverage
     END IF

     DEALLOCATE( Nodes % x, Nodes % y, Nodes % z)
     DEALLOCATE( EdgeNodes % x, EdgeNodes % y, EdgeNodes % z)

CONTAINS

!------------------------------------------------------------------------------
  FUNCTION TRACE(A,N) RESULT(B)
!------------------------------------------------------------------------------
    IMPLICIT NONE
    DOUBLE PRECISION :: A(:,:),B
    INTEGER :: N
!------------------------------------------------------------------------------
    INTEGER :: I
!------------------------------------------------------------------------------
    B = 0.0D0
    DO i = 1,N
       B = B + A(i,i)
    END DO
!------------------------------------------------------------------------------
  END FUNCTION TRACE
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   END FUNCTION ElastBoundaryResidual
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  FUNCTION ElastEdgeResidual( Model,Edge,Mesh,Quant,Perm ) RESULT( Indicator )
!------------------------------------------------------------------------------
     USE ElementDescription
     IMPLICIT NONE

     TYPE(Model_t) :: Model
     INTEGER :: Perm(:)
     REAL(KIND=dp) :: Quant(:), Indicator(2)
     TYPE( Mesh_t ), POINTER    :: Mesh
     TYPE( Element_t ), POINTER :: Edge
!------------------------------------------------------------------------------

     TYPE(Nodes_t) :: Nodes, EdgeNodes
     TYPE(Element_t), POINTER :: Element, Bndry

     INTEGER :: i,j,k,l,n,t,dim,DOFs,En,Pn
     LOGICAL :: stat, GotIt

     REAL(KIND=dp) :: SqrtMetric, Metric(3,3), Symb(3,3,3), dSymb(3,3,3,3)
     REAL(KIND=dp) :: Stress(3,3,2), Jump(3), Identity(3,3)
     REAL(KIND=dp) :: Normal(3), x(4), y(4), z(4)
     REAL(KIND=dp) :: Displacement(3), NodalDisplacement(3,MAX_NODES)
     REAL(KIND=dp) :: YoungsModulus, NodalYoungsModulus(MAX_NODES)
     REAL(KIND=dp) :: PoissonRatio, NodalPoissonRatio(MAX_NODES)
     REAL(KIND=dp) :: Density, NodalDensity(MAX_NODES)
     REAL(KIND=dp) :: Temperature, NodalTemperature(MAX_NODES)
     REAL(KIND=dp) :: Lame1, NodalLame1(MAX_NODES)
     REAL(KIND=dp) :: Lame2, NodalLame2(MAX_NODES)
     REAL(KIND=dp) :: Damping, NodalDamping(MAX_NODES)
     REAL(KIND=dp) :: HeatExpansionCoeff, NodalHeatExpansionCoeff(MAX_NODES)
     REAL(KIND=dp) :: ReferenceTemperature, NodalReferenceTemperature(MAX_NODES)
     REAL(KIND=dp) :: Grad(3,3), DefG(3,3), Strain(3,3), Stress1(3,3), Stress2(3,3)
     REAL(KIND=dp) :: YoungsAverage

     LOGICAL :: PlaneStress

     INTEGER :: eq_id

     TYPE(ValueList_t), POINTER :: Material

     REAL(KIND=dp) :: u, v, w, s, detJ, EdgeBasis(4), Basis(MAX_NODES), &
              dBasisdx(MAX_NODES,3), ddBasisddx(MAX_NODES,3,3)

     REAL(KIND=dp) :: Residual, ResidualNorm, EdgeLength

     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff
!------------------------------------------------------------------------------

!    Initialize:
!    -----------
     SELECT CASE( CurrentCoordinateSystem() )
        CASE( AxisSymmetric, CylindricSymmetric )
           dim = 3
        CASE DEFAULT
           dim = CoordinateSystemDimension()
     END SELECT

     DOFs = dim
     IF ( CurrentCoordinateSystem() == AxisSymmetric ) DOFs = DOFs - 1

     Metric = 0.0d0
     Identity = 0.0d0
     DO i = 1,3
        Metric(i,i) = 1.0d0
        Identity(i,i) = 1.0d0
     END DO
!
!    ---------------------------------------------
     Element => Edge % BoundaryInfo % Left
     n = Element % TYPE % NumberOfNodes

     Element => Edge % BoundaryInfo % Right
     n = MAX( n, Element % TYPE % NumberOfNodes )

     ALLOCATE( Nodes % x(n), Nodes % y(n), Nodes % z(n) )

     En = Edge % TYPE % NumberOfNodes
     ALLOCATE( EdgeNodes % x(En), EdgeNodes % y(En), EdgeNodes % z(En) )

     EdgeNodes % x = Mesh % Nodes % x(Edge % NodeIndexes)
     EdgeNodes % y = Mesh % Nodes % y(Edge % NodeIndexes)
     EdgeNodes % z = Mesh % Nodes % z(Edge % NodeIndexes)

!    Integrate square of jump over edge:
!    ------------------------------------
     ResidualNorm  = 0.0d0
     EdgeLength    = 0.0d0
     Indicator     = 0.0d0
     Grad          = 0.0d0
     YoungsAverage = 0.0d0

     IntegStuff = GaussPoints( Edge )

     DO t=1,IntegStuff % n

        u = IntegStuff % u(t)
        v = IntegStuff % v(t)
        w = IntegStuff % w(t)

        stat = ElementInfo( Edge, EdgeNodes, u, v, w, detJ, &
             EdgeBasis, dBasisdx, ddBasisddx, .FALSE., .FALSE. )

        Normal = NormalVector( Edge, EdgeNodes, u, v, .FALSE. )

        IF ( CurrentCoordinateSystem() == Cartesian ) THEN
           s = IntegStuff % s(t) * detJ
        ELSE
           u = SUM( EdgeBasis(1:En) * EdgeNodes % x(1:En) )
           v = SUM( EdgeBasis(1:En) * EdgeNodes % y(1:En) )
           w = SUM( EdgeBasis(1:En) * EdgeNodes % z(1:En) )

           CALL CoordinateSystemInfo( Metric, SqrtMetric, &
                       Symb, dSymb, u, v, w )
           s = IntegStuff % s(t) * detJ * SqrtMetric
        END IF

        Stress = 0.0d0
        DO i = 1,2
           IF ( i==1 ) THEN
              Element => Edge % BoundaryInfo % Left
           ELSE
              Element => Edge % BoundaryInfo % Right
           END IF

           IF ( ANY( Perm( Element % NodeIndexes ) <= 0 ) ) CYCLE

           Pn = Element % TYPE % NumberOfNodes
           Nodes % x(1:Pn) = Mesh % Nodes % x(Element % NodeIndexes)
           Nodes % y(1:Pn) = Mesh % Nodes % y(Element % NodeIndexes)
           Nodes % z(1:Pn) = Mesh % Nodes % z(Element % NodeIndexes)

           DO j = 1,En
              DO k = 1,Pn
                 IF ( Edge % NodeIndexes(j) == Element % NodeIndexes(k) ) THEN
                    x(j) = Element % TYPE % NodeU(k)
                    y(j) = Element % TYPE % NodeV(k)
                    z(j) = Element % TYPE % NodeW(k)
                    EXIT
                 END IF
              END DO
           END DO

           u = SUM( EdgeBasis(1:En) * x(1:En) )
           v = SUM( EdgeBasis(1:En) * y(1:En) )
           w = SUM( EdgeBasis(1:En) * z(1:En) )

           stat = ElementInfo( Element, Nodes, u, v, w, detJ, &
               Basis, dBasisdx, ddBasisddx, .FALSE., .FALSE. )
!
!          Logical parameters:
!          -------------------
           eq_id = ListGetInteger( Model % Bodies(Element % BodyId) % Values, 'Equation', &
                  minv=1, maxv=Model % NumberOFEquations )

           PlaneStress = ListGetLogical( Model % Equations(eq_id) % Values,'Plane Stress',GotIt )
!
!          Material parameters:
!          --------------------
           k = ListGetInteger( Model % Bodies(Element % BodyId) % Values, 'Material', &
                  minv=1, maxv=Model % NumberOfMaterials )

           Material => Model % Materials(k) % Values

           NodalYoungsModulus(1:En) = ListGetReal( Material,'Youngs Modulus', &
                En, Edge % NodeIndexes, GotIt )
           YoungsModulus = SUM( NodalYoungsModulus(1:En) * EdgeBasis(1:En) )

           NodalPoissonRatio(1:En) = ListGetReal( Material, 'Poisson Ratio', &
                En, Edge % NodeIndexes, GotIt )
           PoissonRatio = SUM( NodalPoissonRatio(1:En) * EdgeBasis(1:En) )

           NodalTemperature(1:En) = ListGetReal( Material,'Temperature', &
                En, Edge % NodeIndexes, GotIt )
           Temperature = SUM( NodalTemperature(1:En) * EdgeBasis(1:En) )

           NodalReferenceTemperature(1:En) = ListGetReal( Material,'Reference Temperature', &
                En, Edge % NodeIndexes, GotIt )
           ReferenceTemperature = SUM( NodalReferenceTemperature(1:En) * EdgeBasis(1:En) )

           NodalDensity(1:En) = ListGetReal( Material,'Density',En,Edge % NodeIndexes, GotIt )
           Density = SUM( NodalDensity(1:En) * EdgeBasis(1:En) )

           NodalDamping(1:En) = ListGetReal( Material,'Damping',En,Edge % NodeIndexes, GotIt )
           Damping = SUM( NodalDamping(1:En) * EdgeBasis(1:En) )

           HeatExpansionCoeff   = 0.0D0

           IF ( PlaneStress ) THEN
              NodalLame1(1:En) = NodalYoungsModulus(1:En) * NodalPoissonRatio(1:En) /  &
                   ( (1.0d0 - NodalPoissonRatio(1:En)**2) )
           ELSE
              NodalLame1(1:En) = NodalYoungsModulus(1:En) * NodalPoissonRatio(1:En) /  &
                   (  (1.0d0 + NodalPoissonRatio(1:En)) * ( 1.0d0 - 2.0d0*NodalPoissonRatio(1:En) ) )
           END IF

           NodalLame2(1:En) = NodalYoungsModulus(1:En)  / ( 2.0d0*(1.0d0 + NodalPoissonRatio(1:En) ) )

           Lame1 = SUM( NodalLame1(1:En) * EdgeBasis(1:En) )
           Lame2 = SUM( NodalLame2(1:En) * EdgeBasis(1:En) )
!
!          Elementwise nodal solution:
!          ---------------------------
           NodalDisplacement = 0.0d0
           DO k=1,DOFs
              NodalDisplacement(k,1:Pn) = Quant( DOFs*Perm(Element % NodeIndexes)-DOFs+k )
           END DO
!
!          Stress tensor on the edge:
!          --------------------------
           Grad = MATMUL(NodalDisplacement(:,1:Pn),dBasisdx(1:Pn,:) )
           DefG = Identity + Grad
           Strain = (TRANSPOSE(Grad)+Grad+MATMUL(TRANSPOSE(Grad),Grad))/2.0D0
           Stress2 = 2.0D0*Lame2*Strain + Lame1*TRACE(Strain,dim)*Identity
           Stress1 = MATMUL(DefG,Stress2)
           Stress(:,:,i) = Stress1

        END DO

        EdgeLength  = EdgeLength + s
        Jump = MATMUL( ( Stress(:,:,1) - Stress(:,:,2)), Normal )
        ResidualNorm = ResidualNorm + s * SUM( Jump(1:dim) ** 2 )

        YoungsAverage = YoungsAverage + s * YoungsModulus

     END DO

     YoungsAverage = YoungsAverage / EdgeLength
     Indicator = EdgeLength * ResidualNorm / YoungsAverage

     DEALLOCATE( Nodes % x, Nodes % y, Nodes % z)
     DEALLOCATE( EdgeNodes % x, EdgeNodes % y, EdgeNodes % z)

CONTAINS

!------------------------------------------------------------------------------
  FUNCTION TRACE(A,N) RESULT(B)
!------------------------------------------------------------------------------
    IMPLICIT NONE
    DOUBLE PRECISION :: A(:,:),B
    INTEGER :: N
!------------------------------------------------------------------------------
    INTEGER :: I
!------------------------------------------------------------------------------
    B = 0.0D0
    DO i = 1,N
       B = B + A(i,i)
    END DO
!------------------------------------------------------------------------------
  END FUNCTION TRACE
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   END FUNCTION ElastEdgeResidual
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   FUNCTION ElastInsideResidual( Model, Element,  &
                      Mesh, Quant, Perm, Fnorm ) RESULT( Indicator )
!------------------------------------------------------------------------------
     USE CoordinateSystems
     USE ElementDescription
!------------------------------------------------------------------------------
     IMPLICIT NONE
!------------------------------------------------------------------------------
     TYPE(Model_t) :: Model
     INTEGER :: Perm(:)
     REAL(KIND=dp) :: Quant(:), Indicator(2), Fnorm
     TYPE( Mesh_t ), POINTER    :: Mesh
     TYPE( Element_t ), POINTER :: Element
!------------------------------------------------------------------------------

     TYPE(Nodes_t) :: Nodes

     INTEGER :: i,j,k,l,m,n,t,dim,DOFs

     LOGICAL :: stat, GotIt

     TYPE( Variable_t ), POINTER :: Var

     REAL(KIND=dp), TARGET :: x(MAX_NODES), y(MAX_NODES), z(MAX_NODES)

     REAL(KIND=dp) :: SqrtMetric, Metric(3,3), Symb(3,3,3), dSymb(3,3,3,3)

     REAL(KIND=dp) :: Density, NodalDensity(MAX_NODES)
     REAL(KIND=dp) :: YoungsModulus, NodalYoungsModulus(MAX_NODES)
     REAL(KIND=dp) :: PoissonRatio, NodalPoissonRatio(MAX_NODES)
     REAL(KIND=dp) :: Lame1, NodalLame1(MAX_NODES)
     REAL(KIND=dp) :: Lame2, NodalLame2(MAX_NODES)
     REAL(KIND=dp) :: Damping, NodalDamping(MAX_NODES)
     REAL(KIND=dp) :: HeatExpansionCoeff, NodalHeatExpansionCoeff(MAX_NODES)
     REAL(KIND=dp) :: ReferenceTemperature, NodalReferenceTemperature(MAX_NODES)
     REAL(KIND=dp) :: NodalDisplacement(3,MAX_NODES), Displacement(3),Identity(3,3)
     REAL(KIND=dp) :: Grad(3,3), DefG(3,3), Strain(3,3), Stress1(3,3), Stress2(3,3)
     REAL(KIND=dp) :: Stress(3,3,MAX_NODES), YoungsAverage, Energy
     REAL(KIND=dp) :: Temperature, NodalTemperature(MAX_NODES), &
              NodalForce(4,MAX_NODES), Veloc(3,MAX_NODES), Accel(3,MAX_NODES)

     INTEGER :: eq_id

     LOGICAL :: PlaneStress, Transient

     REAL(KIND=dp) :: u, v, w, s, detJ, Basis(MAX_NODES), &
        dBasisdx(MAX_NODES,3), ddBasisddx(MAX_NODES,3,3)
     REAL(KIND=dp) :: Residual(3), ResidualNorm, Area
     REAL(KIND=dp), POINTER :: Gravity(:,:)

     TYPE(ValueList_t), POINTER :: Material

     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff
!------------------------------------------------------------------------------

!    Initialize:
!    -----------
     Fnorm = 0.0d0
     Indicator = 0.0d0

     IF ( ANY( Perm( Element % NodeIndexes ) <= 0 ) ) RETURN

     Metric = 0.0d0
     DO i=1,3
        Metric(i,i) = 1.0d0
     END DO

     SELECT CASE( CurrentCoordinateSystem() )
        CASE( AxisSymmetric, CylindricSymmetric )
           dim = 3
        CASE DEFAULT
           dim = CoordinateSystemDimension()
     END SELECT

     DOFs = dim 
     IF ( CurrentCoordinateSystem() == AxisSymmetric ) DOFs = DOFs-1
!
!    Element nodal points:
!    ---------------------
     n = Element % TYPE % NumberOfNodes

     Nodes % x => x(1:n)
     Nodes % y => y(1:n)
     Nodes % z => z(1:n)

     Nodes % x = Mesh % Nodes % x(Element % NodeIndexes)
     Nodes % y = Mesh % Nodes % y(Element % NodeIndexes)
     Nodes % z = Mesh % Nodes % z(Element % NodeIndexes)
!
!    Logical parameters:
!    -------------------
     eq_id = ListGetInteger( Model % Bodies(Element % BodyId) % Values, 'Equation', &
              minv=1, maxv=Model % NumberOfEquations )

     PlaneStress = ListGetLogical( Model % Equations(eq_id) % Values, &
          'Plane Stress',GotIt )
!
!    Material parameters:
!    --------------------
     k = ListGetInteger( Model % Bodies(Element % BodyId) % Values, 'Material', &
             minv=1, maxv=Model % NumberOfMaterials )

     Material => Model % Materials(k) % Values

     NodalYoungsModulus(1:n) = ListGetReal( Material,'Youngs Modulus', &
          n, Element % NodeIndexes, GotIt )

     NodalPoissonRatio(1:n) = ListGetReal( Material, 'Poisson Ratio', &
          n, Element % NodeIndexes, GotIt )

     NodalTemperature(1:n) = ListGetReal( Material,'Temperature', &
          n, Element % NodeIndexes, GotIt )

     NodalReferenceTemperature(1:n) = ListGetReal( Material,'Reference Temperature', &
          n, Element % NodeIndexes, GotIt )

!
!    Check for time dep.
!    -------------------

     IF ( ListGetString( Model % Simulation, 'Simulation Type') == 'transient' ) THEN
        Transient = .TRUE.
        Var => VariableGet( Model % Variables, 'Displacement', .TRUE. )
        DO i=1,DOFs
           Veloc(i,1:n) = Var % PrevValues(DOFs*(Var % Perm(Element % NodeIndexes)-1)+i,1)
           Accel(i,1:n) = Var % PrevValues(DOFs*(Var % Perm(Element % NodeIndexes)-1)+i,2)
        END DO

        NodalDensity(1:n) = ListGetReal( Material,'Density', &
               n, Element % NodeIndexes, GotIt )

        NodalDamping(1:n) = ListGetReal( Material,'Damping', &
               n, Element % NodeIndexes, GotIt )
     ELSE
        Transient = .FALSE.
     END IF

     HeatExpansionCoeff   = 0.0D0

     IF ( PlaneStress ) THEN
        NodalLame1(1:n) = NodalYoungsModulus(1:n) * NodalPoissonRatio(1:n) /  &
             ( (1.0d0 - NodalPoissonRatio(1:n)**2) )
     ELSE
        NodalLame1(1:n) = NodalYoungsModulus(1:n) * NodalPoissonRatio(1:n) /  &
             (  (1.0d0 + NodalPoissonRatio(1:n)) * ( 1.0d0 - 2.0d0*NodalPoissonRatio(1:n) ) )
     END IF

     NodalLame2(1:n) = NodalYoungsModulus(1:n)  / ( 2.0d0*(1.0d0 + NodalPoissonRatio(1:n) ) )
!
!    Elementwise nodal solution:
!    ---------------------------
     NodalDisplacement = 0.0d0
     DO k=1,DOFs
        NodalDisplacement(k,1:n) = Quant( DOFs*Perm(Element % NodeIndexes)-DOFs+k )
     END DO
!
!    Body Forces:
!    ------------
     k = ListGetInteger(Model % Bodies(Element % BodyId) % Values,'Body Force', GotIt, &
                    1, Model % NumberOfBodyForces )

     NodalForce = 0.0d0

     IF ( GotIt .AND. k > 0  ) THEN

        NodalForce(1,1:n) = NodalForce(1,1:n) + ListGetReal( &
             Model % BodyForces(k) % Values, 'Stress BodyForce 1', &
             n, Element % NodeIndexes, GotIt )
        
        NodalForce(2,1:n) = NodalForce(2,1:n) + ListGetReal( &
             Model % BodyForces(k) % Values, 'Stress BodyForce 2', &
             n, Element % NodeIndexes, GotIt )
        
        NodalForce(3,1:n) = NodalForce(3,1:n) + ListGetReal( &
             Model % BodyForces(k) % Values, 'Stress BodyForce 3', &
             n, Element % NodeIndexes, GotIt )

     END IF

     Identity = 0.0D0
     DO i = 1,DIM
        Identity(i,i) = 1.0D0
     END DO
!
!    Values of the stress tensor at node points:
!    -------------------------------------------
     Grad = 0.0d0
     DO i = 1,n
        u = Element % TYPE % NodeU(i)
        v = Element % TYPE % NodeV(i)
        w = Element % TYPE % NodeW(i)

        stat = ElementInfo( Element, Nodes, u, v, w, detJ, &
            Basis, dBasisdx, ddBasisddx, .TRUE., .FALSE. )

        Lame1 = NodalLame1(i)
        Lame2 = NodalLame2(i)

        Grad = 0.0d0
        Grad = MATMUL(NodalDisplacement(:,1:N),dBasisdx(1:N,:) )
        DefG = Identity + Grad
        Strain = (TRANSPOSE(Grad)+Grad+MATMUL(TRANSPOSE(Grad),Grad))/2.0D0
        Stress2 = 2.0D0*Lame2*Strain + Lame1*TRACE(Strain,dim)*Identity
        Stress1 = MATMUL(DefG,Stress2)
        Stress(:,:,i) = Stress1

     END DO
!
!    Integrate square of residual over element:
!    ------------------------------------------
     ResidualNorm = 0.0d0
     Fnorm = 0.0d0
     Area = 0.0d0
     Energy = 0.0d0
     YoungsAverage = 0.0d0

     IntegStuff = GaussPoints( Element )

     DO t=1,IntegStuff % n
        u = IntegStuff % u(t)
        v = IntegStuff % v(t)
        w = IntegStuff % w(t)

        stat = ElementInfo( Element, Nodes, u, v, w, detJ, &
            Basis, dBasisdx, ddBasisddx, .TRUE., .FALSE. )

        IF ( CurrentCoordinateSystem() == Cartesian ) THEN
           s = IntegStuff % s(t) * detJ
        ELSE
           u = SUM( Basis(1:n) * Nodes % x(1:n) )
           v = SUM( Basis(1:n) * Nodes % y(1:n) )
           w = SUM( Basis(1:n) * Nodes % z(1:n) )

           CALL CoordinateSystemInfo( Metric, SqrtMetric, Symb, dSymb, u, v, w )
           s = IntegStuff % s(t) * detJ * SqrtMetric
        END IF
!
!       Residual of the diff.equation:
!       ------------------------------
        Residual = 0.0d0
        DO i = 1,Dim
           Residual(i) = SUM( NodalForce(i,1:n) * Basis(1:n) )

           IF ( Transient ) THEN
              Residual(i) = Residual(i) + SUM( NodalDensity(1:n) * Basis(1:n) ) * &
                                 SUM( Accel(i,1:n) * Basis(1:n) )

              Residual(i) = Residual(i) + SUM( NodalDamping(1:n) * Basis(1:n) ) * &
                                 SUM( Veloc(i,1:n) * Basis(1:n) )
           END IF

           DO j = 1,Dim
              DO k = 1,n
                 Residual(i) = Residual(i) + Stress(i,j,k)*dBasisdx(k,j)
              END DO
           END DO
        END DO
!
!       Dual norm of the load:
!       ----------------------
        DO i = 1,Dim
           Fnorm = Fnorm + s * SUM( NodalForce(i,1:n) * Basis(1:n) ) ** 2
        END DO

        YoungsAverage = YoungsAverage + s * SUM( NodalYoungsModulus(1:n) * Basis(1:n) )

!       Energy:
!       -------
        Grad = 0.0d0
        Grad = MATMUL(NodalDisplacement(:,1:N),dBasisdx(1:N,:) )
        DefG = Identity + Grad
        Strain = (TRANSPOSE(Grad)+Grad+MATMUL(TRANSPOSE(Grad),Grad))/2.0D0
        Stress2 = 2.0D0*Lame2*Strain + Lame1*TRACE(Strain,dim)*Identity
        Stress1 = MATMUL(DefG,Stress2)
        Energy = Energy + s*DDOTPROD(Strain,Stress1,Dim)/2.0d0

        Area = Area + s
        ResidualNorm = ResidualNorm + s * SUM( Residual(1:dim) ** 2 )

     END DO

     YoungsAverage = YoungsAverage / Area
     Fnorm = Energy
     Indicator = Area * ResidualNorm / YoungsAverage

CONTAINS

!------------------------------------------------------------------------------
  FUNCTION TRACE(A,N) RESULT(B)
!------------------------------------------------------------------------------
    IMPLICIT NONE
    DOUBLE PRECISION :: A(:,:),B
    INTEGER :: N
!------------------------------------------------------------------------------
    INTEGER :: I
!------------------------------------------------------------------------------
    B = 0.0D0
    DO i = 1,N
       B = B + A(i,i)
    END DO
!------------------------------------------------------------------------------
  END FUNCTION TRACE
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
  FUNCTION DDOTPROD(A,B,N) RESULT(C)
!------------------------------------------------------------------------------
    IMPLICIT NONE
    DOUBLE PRECISION :: A(:,:),B(:,:),C
    INTEGER :: N
!------------------------------------------------------------------------------
    INTEGER :: I,J
!------------------------------------------------------------------------------
    C = 0.0D0
    DO i = 1,N
       DO j = 1,N
          C = C + A(i,j)*B(i,j)
       END DO
    END DO
!------------------------------------------------------------------------------
  END FUNCTION DDOTPROD
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
   END FUNCTION ElastInsideResidual
!------------------------------------------------------------------------------
