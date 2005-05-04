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
!/******************************************************************************
! *
! * Module defining model type and operations on this type (that was a bold 
! * statement, at the moment just the Model I/O routines are here ...)
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
! *                       Date: 01 Oct 1996
! *
! *                Modified by:
! *
! *       Date of modification:
! *
! *****************************************************************************/

MODULE ModelDescription

    USE MeshUtils
    USE ElementDescription
 
    IMPLICIT NONE

    INTERFACE
      FUNCTION LoadFunction( Quiet,Libname,Procname ) RESULT(Proc)
        USE Types
        CHARACTER :: Libname(*),Procname(*)
        INTEGER :: Quiet
        INTEGER(KIND=AddrInt) :: Proc
      END FUNCTION LoadFunction
    END INTERFACE

    CHARACTER(LEN=1024) :: IncludePath = ' ', OutputPath = ' ', SimulationId = ' '

    INTEGER, PARAMETER :: OutputUnit = 31, RestartUnit = 30, PostFileUnit = 29, &
                          InFileUnit = 28

CONTAINS

!------------------------------------------------------------------------------
  FUNCTION GetProcAddr( str, Quiet ) RESULT( Proc )
DLLEXPORT GetProcAddr
!------------------------------------------------------------------------------
    CHARACTER(LEN=*) :: str
    LOGICAL, OPTIONAL :: Quiet

    INTEGER(KIND=AddrInt) :: Proc
    INTEGER   :: i,j,LEN,q
    CHARACTER :: Libname(MAX_NAME_LEN),Procname(MAX_NAME_LEN)
!------------------------------------------------------------------------------

    LEN = LEN_TRIM(str)

    i = 1
    DO WHILE( i <= LEN )
      IF ( str(i:i) == ' ' ) EXIT
      Libname(i) = str(i:i)
      i = i + 1
    END DO
    Libname(i) = CHAR(0)

    DO WHILE( i <= LEN )
       IF ( str(i:i) /= ' ' ) EXIT
       i = i + 1
    END DO

    j = 1
    DO WHILE( i <= LEN )
      IF (  str(i:i) == ' ' ) EXIT
      Procname(j) = str(i:i)
      i = i + 1
      j = j + 1
    END DO
    ProcName(j) = CHAR(0)

    q = 0
    IF ( PRESENT(Quiet) ) THEN
       IF ( Quiet ) q = 1
    END IF
    Proc = LoadFunction( q,Libname,Procname )
  END FUNCTION GetProcAddr
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE LoadIncludeFile( Model,InFileUnit,FileName,MeshDir,MeshName,ScanOnly )
!------------------------------------------------------------------------------
DLLEXPORT LoadIncludeFile
!------------------------------------------------------------------------------
     TYPE(Model_t) :: Model
     INTEGER :: InFileUnit
     LOGICAL :: ScanOnly
     CHARACTER(LEN=*) :: FileName
     CHARACTER(LEN=*) :: MeshDir,MeshName
!------------------------------------------------------------------------------
     CHARACTER(LEN=1024) :: FName
 
     INTEGER :: k,k0,k1,l
!------------------------------------------------------------------------------

     IF ( INDEX(FileName,':') == 0 .AND. FileName(1:1) /= '/' .AND. &
               FileName(1:1) /= '\\' ) THEN

       k0 = 1
       k1 = INDEX( IncludePath, ';' )
       DO WHILE( k1 >= k0 )
         DO k = k1-1,k0,-1
           IF ( IncludePath(k:k) /= ' ' ) EXIT
         END DO 

         IF ( k >= k0 ) THEN
           WRITE( FName, '(a,a,a)' ) IncludePath(k0:k), '/', &
              TRIM( FileName )
           OPEN( InFileUnit, FILE=TRIM(FName), STATUS='OLD',ERR=10 )
           CALL LoadInputFile( Model, InFileUnit, FName, &
                 MeshDir, MeshName, .FALSE., ScanOnly )
           CLOSE( InFileUnit )
           RETURN
         END IF

10       CONTINUE

         k0 = k1+1
         k1 = INDEX( IncludePath(k0:), ';' ) + k0 - 1
       END DO

       IF ( LEN_TRIM(IncludePath) > 0 ) THEN
         WRITE( FName, '(a,a,a)' ) TRIM(IncludePath(k0:)), '/', &
            TRIM( FileName )

         OPEN( InFileUnit, FILE=TRIM(FName), STATUS='OLD',ERR=20 )
         CALL LoadInputFile( Model, InFileUnit, FName, &
                MeshDir, MeshName, .FALSE., ScanOnly )
         CLOSE( InFileUnit )
         RETURN
       END IF

20     CONTINUE

       OPEN( InFileUnit, FILE=TRIM(FileName), STATUS='OLD' )
       CALL LoadInputFile( Model, InFileUnit, FileName, &
              MeshDir, MeshName, .FALSE., ScanOnly )
       CLOSE( InFileUnit )

     ELSE
       OPEN( InFileUnit, FILE=TRIM(FileName), STATUS='OLD' )
       CALL LoadInputFile( Model, InFileUnit, FileName, &
            MeshDir, MeshName, .FALSE., ScanOnly )
       CLOSE( InFileUnit )
     END IF

!------------------------------------------------------------------------------
  END SUBROUTINE LoadIncludeFile
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  FUNCTION ReloadInputFile( Model ) RESULT(got)
!------------------------------------------------------------------------------
    LOGICAL :: got
    TYPE(Model_t) :: Model
    INTEGER :: pos, posn
    CHARACTER(LEN=MAX_NAME_LEN) :: MeshDir, MeshName

    MeshDir  = ' '
    Meshname = ' '
    CALL LoadInputFile( Model, InFileUnit, ' ', &
        MeshDir, MeshName, .FALSE., .FALSE., got )
!------------------------------------------------------------------------------
  END FUNCTION ReloadInputFile
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  RECURSIVE SUBROUTINE LoadInputFile( Model, InFileUnit, FileName, &
         MeshDir, MeshName, BaseLoad, ScanOnly, Runc )
DLLEXPORT LoadInputFile
!------------------------------------------------------------------------------

    CHARACTER(LEN=*) :: FileName
    TYPE(Model_t) :: Model
    INTEGER :: InFileUnit
    LOGICAL :: BaseLoad
    LOGICAL :: ScanOnly
    LOGICAL, OPTIONAL :: runc
    CHARACTER(LEN=*) :: MeshDir,MeshName
!------------------------------------------------------------------------------

    TYPE( ValueList_t ), POINTER :: List

    INTEGER :: i,j,k,n,Arrayn,TYPE,Sect,N1,N2,BoundaryIndex

    INTEGER(KIND=AddrInt) :: Proc

    CHARACTER(LEN=512) :: name,depname,str,section

    LOGICAL :: SizeGiven
    LOGICAL :: FreeNames, Echo = .FALSE.
    INTEGER :: CheckAbort = 0

    TYPE(Solver_t), POINTER :: ASolvers(:)

    TYPE(MaterialArray_t), POINTER  :: AMaterial(:)
    TYPE(EquationArray_t), POINTER  :: AEquation(:)
    TYPE(BodyArray_t), POINTER      :: ABody(:)
    TYPE(BodyForceArray_t), POINTER :: ABF(:)
    TYPE(InitialConditionArray_t), POINTER  :: AIC(:)
    TYPE(BoundaryConditionArray_t), POINTER :: ABC(:)

    LOGICAL :: FirstTime = .TRUE.

    INTEGER :: IValues(512),nlen
    REAL(KIND=dp) :: Value
    REAL(KIND=dp), POINTER :: ATx(:,:,:), ATt(:), ATtBuf(:), ATxBuf(:,:,:)
!------------------------------------------------------------------------------

!   OPEN( InFileUnit,FILE=TRIM(FileName),STATUS='OLD',ERR=10 )

    NULLIFY( ATx )
    NULLIFY( ATt )
    IF ( .NOT. ScanOnly ) THEN
       ALLOCATE( ATt(512) )
       ALLOCATE( ATx(1,1,512) )
    END IF
!
!------------------------------------------------------------------------------
!   Read model header first
!------------------------------------------------------------------------------
    CheckAbort = 1
    IF ( FirstTime ) THEN
       FirstTime = .FALSE.
       Section = 'simulation'
       CALL CheckKeyword( 'coordinate system', 'string' )
    END IF
 
    IF ( BaseLoad ) THEN
      DO WHILE( ReadAndTrim( InFileUnit, Name, Echo ) )
        IF ( Name(1:1) == ' ' )   CYCLE
        IF ( Name(1:3) == 'end' ) EXIT
        IF ( Name(1:14) == 'check keywords' ) THEN
           k = 16
           IF ( Name(k:k) == '"' ) k = k + 1
           IF ( Name(k:k+5) == 'ignore' )  CheckAbort = 0
           IF ( Name(k:k+3) == 'warn' )    CheckAbort = 1
           IF ( Name(k:k+4) == 'abort' )   CheckAbort = 2
        ELSE IF ( Name(1:7) == 'echo on' ) THEN
           Echo = .TRUE.
        ELSE IF ( Name(1:8) == 'echo off' ) THEN
           Echo = .FALSE.
        ELSE IF ( Name(1:6)  == 'bodies' ) THEN
        ELSE IF ( Name(1:18) == 'initial conditions' ) THEN
        ELSE IF ( Name(1:10) == 'boundaries' ) THEN
        ELSE IF ( Name(1:19) == 'boundary conditions' ) THEN
        ELSE IF ( Name(1:9)  == 'equations' ) THEN
        ELSE IF ( Name(1:7)  == 'solvers' ) THEN
        ELSE IF ( Name(1:9)  == 'materials' ) THEN
        ELSE IF ( Name(1:11) == 'body forces' ) THEN
        ELSE IF ( Name(1:7)  == 'mesh db' ) THEN
          k = 9
          i = 1
          nlen = LEN_TRIM(name)
          DO WHILE( name(k:k) /= ' ' )
            MeshDir(i:i)  = name(k:k)
            Meshname(i:i) = name(k:k)
            k = k + 1
            i = i + 1
          END DO
          MeshDir(i:i) = CHAR(0)

          DO WHILE( k<=nlen .AND. Name(k:k) == ' ' )
            k = k + 1
          END DO

          IF ( k<=nlen ) THEN
             MeshName(i:i) = '/'
             i = i + 1
             DO WHILE( name(k:k) /= ' ' )
               MeshName(i:i) = Name(k:k)
               k = k + 1
               i = i + 1
             END DO
          ELSE
             MeshDir = "." // CHAR(0)
          END IF
          MeshName(i:i) = CHAR(0)
        ELSE IF ( Name(1:6) == 'header' ) THEN
        ELSE IF ( Name(1:12) == 'include path' ) THEN
           IncludePath = Name(14:)
        ELSE IF ( Name(1:17) == 'results directory' ) THEN
           OutputPath = Name(19:)
        ELSE IF ( Name(1:13) == 'simulation id' ) THEN
           SimulationId = Name(15:)
        ELSE
          WRITE( Message, * ) 'Unknown input field in header section: ' // TRIM(Name)
          CALL Fatal( 'Model Input',  Message )
        END IF
      END DO

      NULLIFY( Model % BCs )
      NULLIFY( Model % ICs )
      NULLIFY( Model % Bodies )
      NULLIFY( Model % Solvers )
      NULLIFY( Model % Equations )
      NULLIFY( Model % Materials )
      NULLIFY( Model % Constants )
      NULLIFY( Model % Simulation )
      NULLIFY( Model % BodyForces )
      NULLIFY( Model % Boundaries )
    END IF


!------------------------------------------------------------------------------
    IF ( .NOT. ScanOnly ) THEN
       IF ( .NOT.ASSOCIATED( Model % Boundaries ) ) THEN
         ALLOCATE( Model % Boundaries(Model % NumberOfBoundaries) )
         ALLOCATE( Model % BoundaryId(Model % NumberOfBoundaries) )
         DO i=1,Model % NumberOfBoundaries
           NULLIFY( Model % Boundaries(i) % Values )
           Model % BoundaryId(i) = 0
         END DO
         BoundaryIndex = 0
       END IF
    END IF

    IF ( PRESENT(runc) ) runc = .FALSE.
!------------------------------------------------------------------------------
    DO WHILE( ReadAndTrim( InFileUnit,Section,Echo ) )
!------------------------------------------------------------------------------
      IF ( Section(1:1) == ' ' ) CYCLE

      IF ( Section(1:7) == 'include' ) THEN
        CALL LoadIncludeFile( Model, InFileUnit-1, Section(9:), &
                    MeshDir, MeshName, ScanOnly )
        CYCLE
      END IF

      IF ( Section(1:6) == 'header' ) THEN
         DO WHILE( ReadAndTrim( InFileUnit, Section, Echo ) )
            IF ( Section(1:3) == 'end' ) EXIT
         END DO
         CYCLE
      ELSE IF ( Section(1:5) == 'echo ' .OR. Section(1:6) == 'check ') THEN
         CYCLE
      ELSE IF ( Section(1:3) == 'run' ) THEN
         IF ( PRESENT(runc) ) runc=.TRUE.
         EXIT
      END IF

      FreeNames = CheckAbort <= 0

      ArrayN = 0
      IF ( Section(1:9) == 'constants' ) THEN

         IF ( .NOT. ScanOnly ) THEN
           ArrayN = 1
           List => Model % Constants
         END IF

      ELSE IF ( Section(1:10) == 'simulation' ) THEN

         IF ( .NOT. ScanOnly ) THEN
           ArrayN = 1
           List => Model % Simulation
         END IF

      ELSE IF ( Section(1:18) == 'boundary condition' ) THEN

        IF ( ScanOnly ) THEN
           READ( section(19:),* ) Arrayn
           Model % NumberOFBCs = MAX( Model % NumberOfBCs, Arrayn )
        ELSE
           IF ( .NOT.ASSOCIATED( Model % BCs ) ) THEN
              ALLOCATE( Model % BCs(Model % NumberOfBCs) )
              DO i=1,Model % NumberOfBCs
                 NULLIFY( Model % BCs(i) % Values )
              END DO
           ELSE 
             READ( section(19:),* ) Arrayn
             Model % NumberOfBCs = MAX( Arrayn, Model % NumberOfBCs )

             IF ( SIZE( Model % BCs ) < Model % NumberOfBCs ) THEN
                ALLOCATE( ABC(Model % NumberOfBCs) )
                DO i=1,SIZE(Model % BCs)
                   ABC(i) % Values => Model % BCs(i) % Values
                END DO
                DO i=SIZE(Model % BCs)+1,Model % NumberOfBCs
                   NULLIFY( ABC(i) % Values )
                END DO
                DEALLOCATE( Model % BCs )
                Model % BCs => ABC
             END IF
           END IF

           READ( section(19:),* ) Arrayn
           IF ( Arrayn <= 0 .OR. Arrayn > Model % NumberOfBCs ) THEN
              WRITE( Message, * ) 'Boundary Condition section number: ',Arrayn, &
                            ' exeeds header value.'
              CALL Fatal( 'Model Input', Message )
           END IF
           Model % BCs(ArrayN) % Tag = ArrayN
           List => Model % BCs(Arrayn) % Values
        END IF

        FreeNames = .TRUE.

      ELSE IF ( Section(1:8) == 'boundary' ) THEN

        IF ( ScanOnly ) THEN
           Model % NumberOfBoundaries = Model % NumberOfBoundaries + 1
        ELSE
           IF ( .NOT.ASSOCIATED( Model % Boundaries ) ) THEN
              ALLOCATE( Model % Boundaries(Model % NumberOfBoundaries) )
              ALLOCATE( Model % BoundaryId(Model % NumberOfBoundaries) )
              DO i=1,Model % NumberOfBoundaries
                 NULLIFY( Model % Boundaries(i) % Values )
                 Model % BoundaryId(i) = 0
              END DO
           END IF

           READ( section(9:),* ) Arrayn
           BoundaryIndex = BoundaryIndex + 1
           IF ( BoundaryIndex <= 0 .OR. BoundaryIndex >  &
                 Model % NumberOfBoundaries ) THEN
              WRITE( Message, * ) 'Boundary section number: ',BoundaryIndex, &
                               ' exeeds header value.'
              CALL Fatal( 'Model Input', Message )
           END IF
           Model % BoundaryId(BoundaryIndex) = Arrayn
           List => Model % Boundaries(BoundaryIndex) % Values
        END IF

      ELSE IF ( Section(1:17) == 'initial condition' ) THEN

        IF ( ScanOnly ) THEN
           READ( section(18:),* ) Arrayn
           Model % NumberOFICs = MAX( Model % NumberOfICs, ArrayN )
        ELSE
           IF ( .NOT.ASSOCIATED( Model % ICs ) ) THEN
              ALLOCATE( Model % ICs(Model % NumberOfICs) )
              DO i=1,Model % NumberOfICs
                 NULLIFY( Model % ICs(i) % Values )
              END DO
           ELSE
              READ( section(18:),* ) Arrayn
              Model % NumberOfICs = MAX( Model % NumberOfICs, Arrayn )
              IF ( SIZE( Model % ICs ) < Model % NumberOfICs ) THEN
                ALLOCATE( AIC(Model % NumberOfICs) )
                DO i=1,SIZE(Model % ICs)
                   AIC(i) % Values => Model % ICs(i) % Values
                END DO
                DO i=SIZE(Model % ICs)+1,Model % NumberOfICs
                   NULLIFY( AIC(i) % Values )
                END DO
                DEALLOCATE( Model % ICs )
                Model % ICs => AIC
              END IF
           END IF

           READ( section(18:),* ) Arrayn
           IF ( Arrayn <= 0 .OR. Arrayn > Model % NumberOfICs ) THEN
              WRITE( Message, * ) 'Initial Condition section number: ',Arrayn, &
                          ' exeeds header value.'
              CALL Fatal( 'Model Input', Message )
           END IF
           Model % ICs(ArrayN) % Tag = ArrayN
           List => Model % ICs(Arrayn) % Values
        END IF

        FreeNames = .TRUE.

      ELSE IF ( Section(1:8) == 'material' ) THEN

        IF ( ScanOnly ) THEN
           READ( section(9:),* ) Arrayn
           Model % NumberOFMaterials = MAX( Model % NumberOfMaterials, ArrayN )
        ELSE
           IF ( .NOT.ASSOCIATED( Model % Materials ) ) THEN
              ALLOCATE( Model % Materials(Model % NumberOfMaterials) )
              DO i=1,Model % NumberOfMaterials
                 NULLIFY( Model % Materials(i) % Values )
              END DO
           ELSE
              READ( section(9:),* ) Arrayn
              Model % NumberOfMaterials = MAX( Arrayn, Model % NumberOFMaterials ) 
              IF ( SIZE( Model % Materials ) < Model % NumberOfMaterials ) THEN
                ALLOCATE( AMaterial(Model % NumberOfMaterials) )
                DO i=1,SIZE(Model % Materials)
                   AMaterial(i) % Values => Model % Materials(i) % Values
                END DO
                DO i=SIZE(Model % Materials)+1,Model % NumberOfMaterials
                   NULLIFY( AMaterial(i) % Values )
                END DO
                DEALLOCATE( Model % Materials )
                Model % Materials => AMaterial
              END IF
           END IF

           READ( section(9:),* ) Arrayn
           IF ( Arrayn <= 0 .OR. Arrayn > Model % NumberOfMaterials ) THEN
              WRITE( Message, * ) 'Material section number: ',Arrayn, &
                             ' exeeds header value.'
              CALL Fatal( 'Model Input', Message )
           END IF
           List => Model % Materials(Arrayn) % Values
        END IF

      ELSE IF ( Section(1:10) == 'body force' ) THEN

        IF ( ScanOnly ) THEN
           READ( section(12:),* ) Arrayn
           Model % NumberOFBodyForces = MAX( Model % NumberOFBodyForces, ArrayN)
        ELSE
           IF ( .NOT.ASSOCIATED( Model % BodyForces ) ) THEN
             ALLOCATE( Model % BodyForces(Model % NumberOfBodyForces) )
             DO i=1,Model % NumberOfBodyForces
                NULLIFY( Model % BodyForces(i) % Values )
             END DO
           ELSE
              READ( section(12:),* ) Arrayn
              Model % NumberOFBodyForces = MAX( Arrayn, Model % NumberOfBodyForces )
              IF ( SIZE( Model % BodyForces ) < Model % NumberOfBodyForces ) THEN
                 ALLOCATE( ABF(Model % NumberOfBodyForces) )
                 DO i=1,SIZE(Model % BodyForces)
                    ABF(i) % Values => Model % BodyForces(i) % Values
                 END DO
                 DO i=SIZE(Model % BodyForces)+1,Model % NumberOfBodyForces
                    NULLIFY( ABF(i) % Values )
                 END DO
                 DEALLOCATE( Model % BodyForces )
                 Model % BodyForces => ABF
              END IF
           END IF

           READ( section(12:),* ) Arrayn
           IF ( Arrayn <= 0 .OR. Arrayn > Model % NumberOfBodyForces ) THEN
              WRITE( Message, * ) 'Body Force section number: ',Arrayn, &
                          ' exeeds header value.'
              CALL Fatal( 'Model Input', Message )
           END IF
           List => Model % BodyForces(Arrayn) % Values
        END IF

      ELSE IF ( Section(1:8) == 'equation' ) THEN

        IF ( ScanOnly ) THEN
           READ( section(9:),* ) Arrayn
           Model % NUmberOfEquations = MAX( Model % NumberOFEquations, ArrayN )
        ELSE
           IF ( .NOT.ASSOCIATED( Model % Equations ) ) THEN
             ALLOCATE( Model % Equations(Model % NumberOfEquations) )
             DO i=1,Model % NumberOfEquations
               NULLIFY( Model % Equations(i) % Values )
             END DO
           ELSE
              READ( section(9:),* ) Arrayn
              Model % NumberOFEquations = MAX( Arrayn, Model % NumberOFEquations )
              IF ( SIZE( Model % Equations ) < Model % NumberOfEquations ) THEN
                ALLOCATE( AEquation(Model % NumberOfEquations) )
                DO i=1,SIZE(Model % Equations)
                   AEquation(i) % Values => Model % Equations(i) % Values
                END DO
                DO i=SIZE(Model % Equations)+1,Model % NumberOfEquations
                   NULLIFY( AEquation(i) % Values )
                END DO
                DEALLOCATE( Model % Equations )
                Model % Equations => AEquation
              END IF
           END IF

           READ( section(9:),* ) Arrayn
           IF ( Arrayn <= 0 .OR. Arrayn > Model % NumberOfEquations ) THEN
              WRITE( Message, * ) 'Equation section number: ',Arrayn, &
                           ' exeeds header value.'
              CALL Fatal( 'Model Input', Message )
           END IF
           List => Model % Equations(ArrayN) % Values
        END IF

        FreeNames = .TRUE.

      ELSE IF ( Section(1:4) == 'body' ) THEN

        IF ( ScanOnly ) THEN
           READ( section(5:),* ) Arrayn
           Model % NumberOFBodies = MAX( Model % NumberOFBodies, ArrayN )
        ELSE
           IF ( .NOT.ASSOCIATED( Model % Bodies ) ) THEN
             ALLOCATE( Model % Bodies(Model % NumberOfBodies) )
             DO i=1,Model % NumberOfBodies
               NULLIFY( Model % Bodies(i) % Values )
             END DO
           ELSE
              READ( section(5:),* ) Arrayn
              Model % NumberOFBodies = MAX( Arrayn, Model % NumberOFBodies )
              IF ( SIZE( Model % Bodies ) < Model % NumberOfBodies ) THEN
                 ALLOCATE( ABody(Model % NumberOfBodies) )
                 DO i=1,SIZE(Model % Bodies)
                    ABody(i) % Values => Model % Bodies(i) % Values
                 END DO
                 DO i=SIZE(Model % Bodies)+1,Model % NumberOfBodies
                    NULLIFY( ABody(i) % Values )
                 END DO
                 DEALLOCATE( Model % Bodies )
                 Model % Bodies => ABody
              END IF
           END IF

           READ( section(5:),* ) Arrayn
           IF ( Arrayn <= 0 .OR. Arrayn > Model % NumberOfBodies ) THEN
              WRITE( Message, * ) 'Body section number: ',Arrayn, &
                        ' exeeds header value. Aborting. '
              CALL Fatal( 'Model Input', Message )
           END IF
           List => Model % Bodies(Arrayn) % Values
        END IF

      ELSE IF ( Section(1:6) == 'solver' ) THEN

        IF ( ScanOnly ) THEN
           READ( section(7:),* ) Arrayn
           Model % NumberOfSolvers = MAX( Model % NumberOfSolvers, ArrayN )
        ELSE
           IF ( .NOT.ASSOCIATED( Model % Solvers ) ) THEN
             ALLOCATE( Model % Solvers(Model % NumberOfSolvers) )
             DO i=1,Model % NumberOfSolvers
                Model % Solvers(i) % PROCEDURE = 0
                NULLIFY( Model % Solvers(i) % Matrix )
                NULLIFY( Model % Solvers(i) % Values )
                NULLIFY( Model % Solvers(i) % ActiveElements )
                Model % Solvers(i) % NumberOfActiveElements = 0
             END DO
           ELSE
              READ( section(7:),* ) Arrayn
              Model % NumberOfSolvers = MAX( Arrayn, Model % NumberOfSolvers )
              IF ( SIZE(Model % Solvers) < Model % NumberOfSolvers ) THEN
                ALLOCATE( ASolvers(Model % NumberOfSolvers) )
                DO i=1,SIZE(Model % Solvers)
                   ASolvers(i) = Model % Solvers(i)
                END DO
                DO i=SIZE(Model % Solvers)+1,Model % NumberOfSolvers
                   ASolvers(i) % PROCEDURE = 0
                   NULLIFY( ASolvers(i) % Matrix )
                   NULLIFY( ASolvers(i) % Mesh )
                   NULLIFY( ASolvers(i) % Values )
                   NULLIFY( ASolvers(i) % ActiveElements )
                   ASolvers(i) % NumberOfActiveElements = 0
                END DO
                DEALLOCATE( Model % Solvers )
                Model % Solvers => ASolvers
              END IF
           END IF

           READ( section(7:),* ) Arrayn
           IF ( Arrayn <= 0 .OR. Arrayn > Model % NumberOfSolvers ) THEN
              WRITE( Message, * ) 'Solver section number: ',Arrayn, &
                               ' exeeds header value. Aborting. '
              CALL Fatal( 'Model Input', Message )
           END IF
           List => Model % Solvers(Arrayn) % Values
        END IF
      ELSE
        WRITE( Message, * ) 'Unknown input section name: ',TRIM(Section)
        CALL Fatal( 'Model Input', Message )
      END IF
!------------------------------------------------------------------------------
      IF ( .NOT. ScanOnly .AND. ArrayN == 0 ) CYCLE

      CALL SectionContents( InFileUnit, ScanOnly, Atx, Att )
!------------------------------------------------------------------------------
    END DO
!------------------------------------------------------------------------------

!   CLOSE( InFileUnit )

    IF ( .NOT. ScanOnly )  THEN
      IF ( ASSOCIATED(ATx) ) DEALLOCATE( ATx )
      IF ( ASSOCIATED(ATt) ) DEALLOCATE( ATt )

      ! Add default equation, material, ic, bodyforce, and body if not given:
      ! ---------------------------------------------------------------------
      IF ( Model % NumberOFEquations <= 0 ) THEN
         Model % NumberOfEquations = 1
         ALLOCATE( Model % Equations(1) )
         NULLIFY( Model % Equations(1) % Values )
         CALL ListAddIntegerArray( Model % Equations(1) % Values, 'Active Solvers', &
             Model % NumberOFSolvers, (/ (i,i=1,Model % NumberOfSolvers) /) )
         CALL ListAddString ( Model % Equations(1) % Values, 'Name', 'Default Equation 1' )
      END IF

      IF ( Model % NumberOfMaterials <= 0 ) THEN
         Model % NumberOfMaterials = 1
         ALLOCATE( Model % Materials(1) )
         NULLIFY( Model % Materials(1) % Values )
         CALL ListAddString ( Model % Materials(1) % Values, 'Name', 'Default Material 1' )
      END IF

      IF ( Model % NumberOfBodyForces <= 0 ) THEN
         Model % NumberOfBodyForces = 1
         ALLOCATE( Model % BodyForces(1) )
         NULLIFY( Model % BodyForces(1) % Values )
         CALL ListAddString ( Model % BodyForces(1) % Values, 'Name','Default Body Force 1' )
      END IF

      IF ( Model % NumberOfICs <= 0 ) THEN
         Model % NumberOfICs = 1
         ALLOCATE( Model % ICs(1) )
         NULLIFY( Model % ICs(1) % Values )
         CALL ListAddString ( Model % ICs(1) % Values, 'Name','Default IC 1' )
      END IF

      IF ( Model % NumberOfBodies <= 0 ) THEN
         Model % NumberOfBodies = 1
         ALLOCATE( Model % Bodies(1) )
         NULLIFY( Model % Bodies(1) % Values )
         CALL ListAddString(  Model % Bodies(1) % Values, 'Name', 'Default Body 1' )
         CALL ListAddInteger( Model % Bodies(1) % Values, 'Equation',   1 )
         CALL ListAddInteger( Model % Bodies(1) % Values, 'Material',   1 )
         CALL ListAddInteger( Model % Bodies(1) % Values, 'Body Force', 1 )
         CALL ListAddInteger( Model % Bodies(1) % Values, 'Initial Condition', 1 )
      END IF
      ! -- done adding default fields
    END IF

    RETURN

10  CONTINUE

    WRITE( Message, * ) 'Cannot find input file: ', TRIM(FileName)
    CALL Warn( 'Model Input', Message )

CONTAINS

    SUBROUTINE CheckKeyWord( Name,TYPE,ReturnType )
       USE HashTable

       CHARACTER(LEN=*) :: Name,TYPE
       LOGICAL, OPTIONAL :: ReturnType
       INTEGER :: i,j, n, istat
       TYPE(HashTable_t), POINTER :: Hash
       TYPE(HashValue_t), POINTER :: Value
       LOGICAL :: FirstTime = .TRUE.,lstat
       SAVE FirstTime, Hash
       CHARACTER(LEN=MAX_NAME_LEN) :: str,str1
       EXTERNAL ENVIR

       IF ( PRESENT( ReturnType ) ) ReturnType = .FALSE.

       IF ( CheckAbort <= 0 ) RETURN

       IF ( FirstTime ) THEN
!
!         First time in, read the SOLVER.KEYWORDS database, and
!         build up a local hash table for it:
!         ------------------------------------------------------
          str = 'ELMER_LIB'; str(10:10) = CHAR(0)
          CALL envir( str,str1,k ) 

          IF ( k > 0  ) THEN
            str1 = str1(1:k) // '/SOLVER.KEYWORDS'
          ELSE
            str = 'ELMER_HOME'; str(11:11) = CHAR(0)
            CALL envir( str,str1,k ) 
            str1 = str1(1:k) // '/lib/' // 'SOLVER.KEYWORDS'
          END IF
          OPEN( 1, FILE=TRIM(str1), STATUS='OLD', ERR=10 )

!
!         Initially 50 buckets, on avarage MAX 4 entries / bucket:
!         --------------------------------------------------------
          hash => HashCreate( 50,4 )
          IF ( .NOT. ASSOCIATED( hash ) ) THEN
             IF ( CheckAbort <= 1 ) THEN
               CALL Warn( 'Model Input', 'Can not create the hash table for SOLVER.KEYWORDS.' )
               CALL Warn( 'Model Input', 'keyword checking disabled.' )
               CheckAbort = 0
               RETURN
             ELSE
               CALL Fatal( 'Model Input','Can not create the hash table for SOLVER.KEYWORDS.' )
             END IF
          END IF

5         CONTINUE

!
!         Read the keywords file row by row and add to the hash table:
!         ------------------------------------------------------------
          DO WHILE( ReadAndTrim( 1, str ) )
             i = INDEX( str, ':' )
             j = INDEX( str, "'" )
             IF ( i <= 0 .OR. j<= 0 ) CYCLE
             str1 = str(1:i-1) // ':' //  str(j+1:LEN_TRIM(str)-1)

             ALLOCATE( Value, STAT=istat )

             IF ( istat /= 0 ) THEN
                IF ( CheckAbort <= 1 ) THEN
                  CALL Warn( 'Model Input', 'Can not allocate the hash table entry for SOLVER.KEYWORDS.' )
                  CALL Warn( 'Model Input', ' keyword checking disabled.' )
                  CheckAbort = 0
                  RETURN
                ELSE
                  CALL Fatal( 'Model Input', 'Can not allocate the hash table entry for SOLVER.KEYWORDS.' )
                END IF
             END IF

             Value % TYPE = str(i+1:j-3)

             lstat = HashAdd( hash, str1, Value )
             IF ( .NOT. lstat ) THEN
                IF ( CheckAbort <= 1 ) THEN
                   CALL Warn( 'Model Input', 'Hash table build error. Keyword checking disabled.' )
                   CheckAbort = 0
                   RETURN
                ELSE
                   CALL Fatal( 'Model Input', 'Hash table build error.' )
                END IF
             END IF
          END DO
          CLOSE(1)

          IF ( FirstTime ) THEN
             FirstTime = .FALSE.
             OPEN( 1, FILE='SOLVER.KEYWORDS', STATUS='OLD', ERR=6 )
             CALL Info( 'Model Input', 'Found local SOLVER.KEYWORDS file, adding keywords to runtime database.' )
             GOTO 5
6            CONTINUE
          END IF
       END IF

!------------------------------------------------------------------------------

        IF ( Section(1:9) == 'constants' ) THEN
           str =  'constants: '
        ELSE IF ( Section(1:10) == 'simulation' ) THEN
           str =  'simulation: '
        ELSE IF ( Section(1:18) == 'boundary condition' ) THEN
           str =  'bc: '
        ELSE IF ( Section(1:8) == 'boundary' ) THEN
          str =  'boundary: '
        ELSE IF ( Section(1:17) == 'initial condition' ) THEN
          str =  'ic: '
        ELSE IF ( Section(1:8) == 'material' ) THEN
          str =  'material: '
        ELSE IF ( Section(1:10) == 'body force' ) THEN
          str =  'bodyforce: '
        ELSE IF ( Section(1:8) == 'equation' ) THEN
          str =  'equation: '
        ELSE IF ( Section(1:4) == 'body' ) THEN
          str =  'body: '
        ELSE IF ( Section(1:6) == 'solver' ) THEN
          str =  'solver: '
        END IF

        str = TRIM(str) // TRIM(Name)

!------------------------------------------------------------------------------

       Value => HashValue( Hash, str )
       IF ( ASSOCIATED( Value ) ) THEN
          IF ( PRESENT( ReturnType ) ) THEN
             ReturnType = .TRUE.
             TYPE = Value % TYPE
          END IF
          IF  ( HashEqualKeys( Value % TYPE, TYPE ) ) RETURN
       END IF

       IF ( PRESENT( ReturnType ) ) ReturnType = .FALSE.

       IF ( .NOT.ASSOCIATED(Value) .AND. (CheckAbort <= 1 .OR. FreeNames) ) THEN
          WRITE( Message, * ) 'Unknown keyword: [', TRIM(name), &
                    '] in section: [', TRIM(Section), ']'
          CALL Warn( 'Model Input', Message )
       ELSE
          IF ( ASSOCIATED( Value ) ) THEN
             WRITE( Message, * ) 'Keyword: [', TRIM(name), &
                    '] in section: [', TRIM(Section), ']',  &
                    ' is given wrong type: [', TRIM(TYPE),  &
                    '], should be of type: [', TRIM(Value % TYPE),']'
          ELSE
             WRITE( Message, * ) 'Unknown keyword: [', TRIM(name), &
               '] in section: [', TRIM(Section), '].'
          END IF
          CALL Fatal( 'Model Input', Message )
       END IF

       RETURN

10     CONTINUE

       IF ( CheckAbort <= 1 ) THEN
          CALL Warn( 'Model Input', 'Keyword check requested, but SOLVER.KEYWORDS' // &
                 ' database not available.' )
       ELSE
          CALL Fatal( 'Model Input', 'Keyword check requested, but SOLVER.KEYWORDS' // &
                 ' database not available.' )
       END IF
!------------------------------------------------------------------------------
    END SUBROUTINE
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
    RECURSIVE SUBROUTINE SectionContents( InFileUnit, ScanOnly, ATx, Att )
!------------------------------------------------------------------------------

      INTEGER :: InFileUnit

      REAL(KIND=dp), POINTER :: Atx(:,:,:), ATt(:)

      CHARACTER(LEN=MAX_NAME_LEN) :: TypeString
      LOGICAL :: ReturnType, ScanOnly
      CHARACTER(LEN=MAX_NAME_LEN) :: Name

      INTEGER :: LEN

      DO WHILE( ReadAndTrim( InFileUnit,name,Echo ) )

        IF ( Name(1:7) == 'include' ) THEN
          OPEN( InFileUnit-1,FILE=TRIM(Name(9:)),STATUS='OLD',ERR=10 )
          CALL SectionContents( InFileUnit-1,ScanOnly,Atx,Att )
          CLOSE( InFileUnit-1 )
          CYCLE

10        CONTINUE

          WRITE( Message, * ) 'Cannot find include file: ', Name(9:40)
          CALL Warn( 'Model Input', Message )
          CYCLE
        END IF

        IF ( Name(1:1) == ' ' )  CYCLE
        IF ( Name(1:3) == 'end' ) THEN
          EXIT
        END IF

        TYPE = LIST_TYPE_CONSTANT_SCALAR
        N1   = 1
        N2   = 1
        SizeGiven = .FALSE.
        DO WHILE( ReadAndTrim(InFileUnit,str,echo) ) 

20        CONTINUE

          LEN = LEN_TRIM(str)

          IF ( str(1:4) == 'real' ) THEN

             CALL CheckKeyWord( Name,'real' )

             Proc = 0
             IF ( str(6:14) == 'procedure' ) THEN

               IF ( .NOT. ScanOnly ) THEN
                  Proc = GetProcAddr( str(16:) )

                  SELECT CASE( TYPE )
                  CASE( LIST_TYPE_CONSTANT_SCALAR )

                    IF ( SizeGiven ) THEN
                      CALL ListAddConstRealArray( List,Name,N1,N2, &
                             ATx(1:N1,1:N2,1),Proc )
                    ELSE
                      CALL ListAddConstReal( List,Name,Value,Proc )
                    END IF
   
                  CASE( LIST_TYPE_VARIABLE_SCALAR )

                    IF ( SizeGiven ) THEN
                      CALL ListAddDepRealArray( List,Name,Depname,1,ATt, &
                            N1,N2,ATx(1:N1,1:N2,1:1),Proc )
                    ELSE
                      CALL ListAddDepReal( List,Name,Depname,1,ATt,ATx,Proc )
                    END IF
                  END SELECT
               END IF

             ELSE IF ( str(6:9) == 'matc' ) THEN

               IF ( .NOT. ScanOnly ) THEN

                  SELECT CASE( TYPE )
                  CASE( LIST_TYPE_CONSTANT_SCALAR )

                    IF ( SizeGiven ) THEN
                       CALL ListAddConstRealArray( List,Name,N1,N2, ATx(1:N1,1:N2,1), Proc, str(11:) )
                    ELSE
                      CALL ListAddConstReal( List,Name,Value,Proc, str(11:) )
                    END IF
   
                  CASE( LIST_TYPE_VARIABLE_SCALAR )

                    IF ( SizeGiven ) THEN
                      CALL ListAddDepRealArray( List,Name,Depname,1,ATt, &
                            N1,N2,ATx(1:N1,1:N2,1:n),Proc, str(11:) )
                    ELSE
                      CALL ListAddDepReal( List,Name,Depname,1,ATt,ATx,Proc, str(11:) )
                    END IF
                  END SELECT
               END IF

             ELSE

               SELECT CASE( TYPE )
               CASE( LIST_TYPE_CONSTANT_SCALAR )
                  IF ( .NOT. ScanOnly ) THEN
                     k = 0
                     DO i=1,N1
                        DO j=1,N2
                           DO WHILE( k <= LEN )
                              k = k + 1
                              IF ( str(k:k) == ' ' ) EXIT
                           END DO
 
                           DO WHILE( k <= LEN )
                             k = k + 1
                             IF ( str(k:k) /= ' ' ) EXIT
                           END DO
 
                           IF ( k > LEN ) CALL SyntaxError( Section, Name,str )
 
                           READ( str(k:),* ) ATx(i,j,1)
                        END DO
                     END DO
 
                     IF ( SizeGiven ) THEN
                       CALL ListAddConstRealArray( List,Name,N1,N2, &
                              ATx(1:N1,1:N2,1) )
                     ELSE
                       CALL ListAddConstReal( List,Name,ATx(1,1,1) )
                     END IF
                  END IF
  
               CASE( LIST_TYPE_VARIABLE_SCALAR )
                 n = 0
 
                 DO WHILE( ReadAndTrim(InFileUnit,str,Echo) )
                   IF ( str(1:3) == 'end' ) EXIT
                   IF ( str(1:1) == ' '  ) CYCLE
 
                   IF ( .NOT. ScanOnly ) THEN
                      LEN = LEN_TRIM(str)
 
                      n = n + 1
                      IF ( n > SIZE(ATt) ) THEN
                         ALLOCATE( ATtBuf( SIZE(ATt)+512) )
                         ATtBuf(1:n-1) = ATt(1:n-1)
                         DEALLOCATE( ATt )
                         ATt => ATtBuf
 
                         ALLOCATE( ATxBuf( n1,n2,SIZE(ATt)+512) )
                         ATxBuf(1:n1,1:n2,1:n-1) = ATx(1:n1,1:n2,1:n-1)
                         DEALLOCATE( ATx )
                         ATx => ATxBuf
                      END IF
 
                      READ( str,* ) ATt(n)
 
                      k = 0
                      DO i=1,N1
                        DO j=1,N2
                          DO WHILE( k <= LEN )
                            k = k + 1
                            IF ( str(k:k) == ' ') EXIT
                          END DO
 
                          DO WHILE( k <= LEN )
                            k = k + 1
                            IF ( str(k:k) /= ' ') EXIT
                          END DO
 
                          IF ( k > LEN ) CALL SyntaxError( Section, Name,str )
 
                          READ( str(k:),* ) ATx(i,j,n)
                        END DO
                      END DO
 
                      IF ( SizeGiven ) THEN
                        CALL ListAddDepRealArray( List,Name,Depname,n,ATt(1:n), &
                                 N1,N2,ATx(1:N1,1:N2,1:N) )
                      ELSE
                        CALL ListAddDepReal( List,Name,Depname,n,ATt(1:n), &
                                      ATx(1,1,1:N) )
                      END IF
                   END IF
                 END DO
               END SELECT
             END IF
             EXIT

          ELSE IF ( str(1:7) == 'logical' ) THEN

            CALL CheckKeyWord( Name,'logical' )

            IF ( .NOT. ScanOnly ) THEN
               IF ( str(9:12) == 'true' .OR. str(9:9) == '1' ) THEN
                 CALL ListAddLogical( List,Name,.TRUE. )
               ELSE 
                 CALL ListAddLogical( List,Name,.FALSE. )
               END IF
            END IF
            EXIT

          ELSE IF ( str(1:7) == 'integer' ) THEN

            CALL CheckKeyWord( Name,'integer' )

            IF ( .NOT. ScanOnly ) THEN
               Proc = 0
               IF ( str(9:17) == 'procedure' ) THEN
                 Proc = GetProcAddr( str(9:) )
                 IF ( SizeGiven ) THEN
                   CALL ListAddIntegerArray( List,Name,N1,IValues,Proc )
                 ELSE
                   CALL ListAddInteger( List,Name,k,Proc )
                 END IF
               ELSE
                 IF ( SizeGiven ) THEN
                   k = 0
                   DO i=1,N1
                     DO WHILE( k <= LEN )
                        k = k + 1
                        IF ( str(k:k) == ' ') EXIT
                     END DO

                     DO WHILE( k <= LEN )
                       k = k + 1
                       IF ( str(k:k) /= ' ') EXIT
                     END DO

                     IF ( k > LEN ) CALL SyntaxError( Section, Name,str )

                     READ( str(k:),* ) IValues(i)
                   END DO
                   CALL ListAddIntegerArray( List,Name,N1,IValues )
                 ELSE
                   READ( str(9:),* ) k 
                   CALL ListAddInteger( List,Name,k )
                 END IF
               END IF
            END IF
            EXIT

          ELSE IF ( str(1:6) == 'string' ) THEN

            CALL CheckKeyWord( Name,'string' )

            IF ( .NOT. ScanOnly ) CALL ListAddString( List,Name,str(8:) )
            EXIT

          ELSE IF ( str(1:4) == 'file' ) THEN

            CALL CheckKeyWord( Name,'file' )

            IF ( .NOT. ScanOnly ) CALL ListAddString( List,Name,str(6:),.FALSE. )
            EXIT

          ELSE IF ( str(1:8) == 'variable' ) THEN

            DO k=MAX_NAME_LEN,1,-1
              IF ( str(k:k) /= ' ' ) EXIT 
            END DO

            Depname = ' '
            Depname(1:k-9) = str(10:k)
            TYPE = LIST_TYPE_VARIABLE_SCALAR

          ELSE IF ( str(1:6) == 'equals' ) THEN

            IF ( .NOT. ScanOnly ) THEN
               DO k=MAX_NAME_LEN,1,-1
                 IF ( str(k:k) /= ' ' ) EXIT 
               END DO

               Depname = ' '
               Depname(1:k-7) = str(8:k)

               n = 2
               IF ( n > SIZE( ATt ) ) THEN
                  DEALLOCATE( ATt, ATx )
                  ALLOCATE( ATt(2), ATx(1,1,2) )
               END IF

               ATt(1) = 0
               ATt(2) = 1
               ATx(1,1,1) = 0
               ATx(1,1,2) = 1
               CALL ListAddDepReal( List,Name,Depname,n,ATt(1:n), ATx(1,1,1:n) )
            END IF
            EXIT

          ELSE IF ( str(1:4) == 'size' ) THEN
            N1 = 1
            N2 = 1
            READ( str(5:),*,err=1,END=1) N1,N2
1           CONTINUE

            IF ( .NOT. ScanOnly ) THEN
               IF ( ASSOCIATED( ATx ) ) DEALLOCATE( ATx )
               ALLOCATE( ATx(N1,N2,512) )
               IF ( ASSOCIATED( ATt ) ) DEALLOCATE( ATt )
               ALLOCATE( ATt(512) )
            END IF

            SizeGiven = .TRUE.

          ELSE IF ( str(1:7) == '-remove' ) THEN

            IF ( .NOT. ScanOnly ) CALL ListRemove( List, Name )
            EXIT

          ELSE 

            ReturnType = .TRUE.
            CALL CheckKeyWord( Name, TypeString, ReturnType )
            IF ( ReturnType ) THEN 
               str = TRIM( TypeString ) // ' ' // str
               GOTO 20
            END IF
            CALL SyntaxError( Section, Name,str )

          END IF
!------------------------------------------------------------------------------
        END DO
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
        IF ( .NOT. ScanOnly ) THEN
           IF ( Section(1:9) == 'constants' ) THEN
             Model % Constants => List
           ELSE IF ( Section(1:10) == 'simulation' ) THEN
             Model % Simulation => List
           ELSE IF ( Section(1:18) == 'boundary condition' ) THEN
             Model % BCs(Arrayn) % Values => List
           ELSE IF ( Section(1:8) == 'boundary' ) THEN
             Model % Boundaries(BoundaryIndex) % Values => List
           ELSE IF ( Section(1:17) == 'initial condition' ) THEN
             Model % ICs(Arrayn) % Values => List
           ELSE IF ( Section(1:8) == 'material' ) THEN
             Model % Materials(Arrayn) % Values => List
           ELSE IF ( Section(1:10) == 'body force' ) THEN
             Model % BodyForces(Arrayn) % Values => List
           ELSE IF ( Section(1:8) == 'equation' ) THEN
             Model % Equations(Arrayn) % Values  => List
           ELSE IF ( Section(1:4) == 'body' ) THEN
             Model % Bodies(Arrayn) % Values => List
           ELSE IF ( Section(1:6) == 'solver' ) THEN
             Model % Solvers(Arrayn) % Values => List
           END IF
        END IF
!------------------------------------------------------------------------------
      END DO
!------------------------------------------------------------------------------
      END SUBROUTINE SectionContents
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
      SUBROUTINE SyntaxError( Section, Name, LastString )
!------------------------------------------------------------------------------
        CHARACTER(LEN=*) :: Section, Name, LastString

         CALL Error( 'Model Input', ' ' )
         WRITE( Message, * ) 'Unknown specifier: [',TRIM(LastString),']'
         CALL Error( 'Model Input', Message )
         WRITE( Message, * ) 'In section: [', TRIM(Section), ']'
         CALL Error( 'Model Input', Message )
         WRITE( Message, * ) 'For property name:[',TRIM(Name),']'
         CALL Fatal( 'Model Input', Message )
!------------------------------------------------------------------------------
      END SUBROUTINE SyntaxError
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
  END SUBROUTINE LoadInputFile
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  SUBROUTINE LoadGebhardtFactors( Mesh,FileName )
DLLEXPORT LoadGebhardtFactors
!------------------------------------------------------------------------------
    TYPE(Mesh_t), POINTER :: Mesh
    CHARACTER(LEN=*) FileName
!------------------------------------------------------------------------------

    INTEGER, ALLOCATABLE :: Mapping(:)
    INTEGER :: i,j,k,l,n,m,p
    REAL(KIND=dp) :: s
    CHARACTER(LEN=MAX_NAME_LEN) :: FName
    TYPE(Element_t), POINTER :: elm,celm

!------------------------------------------------------------------------------

    IF ( LEN_TRIM(Mesh % Name) > 0 ) THEN
      FName = TRIM(OutputPath) // '/' // TRIM(Mesh % Name) // '/' // TRIM(FileName)
    ELSE
      FName = TRIM(FileName)
    END IF
    OPEN( 1,file = TRIM(FName),err=10 )

    CALL Info( 'LoadGebhardtFactors', 'Start', Level=5 )

    READ(1,*) n
    ALLOCATE( mapping(n) )
    DO i=1,n
      READ(1,*) j,mapping(i)
    END DO

    DO i=1,n
      READ(1,*) m
      DO j=1,m
        READ(1,*) k,l,s
        k = mapping(k)
        l = mapping(l)
        IF ( .NOT.ASSOCIATED( &
          mesh % elements(k) % boundaryinfo % gebhardtfactors % factors) ) THEN
          ALLOCATE(  &
          mesh % elements(k) % boundaryinfo % gebhardtfactors % factors(m), &
          mesh % elements(k) % boundaryinfo % gebhardtfactors % elements(m) )
          mesh % elements(k) % boundaryinfo % gebhardtfactors % numberoffactors = m
        ELSE IF ( mesh % elements(k) % boundaryinfo % gebhardtfactors % numberoffactors/=m ) THEN
          DEALLOCATE(  &
          mesh % elements(k) % boundaryinfo % gebhardtfactors % factors, &
          mesh % elements(k) % boundaryinfo % gebhardtfactors % elements )
          ALLOCATE(  &
          mesh % elements(k) % boundaryinfo % gebhardtfactors % factors(m), &
          mesh % elements(k) % boundaryinfo % gebhardtfactors % elements(m) )
          mesh % elements(k) % boundaryinfo % gebhardtfactors % numberoffactors = m
        END IF
        mesh % elements(k) % boundaryinfo % gebhardtfactors % numberofimplicitfactors = &
            mesh % elements(k) % boundaryinfo % gebhardtfactors % numberoffactors
      END DO
    END DO

    REWIND(1)

    READ(1,*) n

    DO i=1,n
      READ(1,*) j,mapping(i)
    END DO

    DO i=1,n
      READ(1,*) m
      DO j=1,m
        READ(1,*) k,l,s
        k = mapping(k)
        l = mapping(l)
        mesh % elements(k) % boundaryinfo % gebhardtfactors % elements(j) = l
        mesh % elements(k) % boundaryinfo % gebhardtfactors % factors(j)  = s
      END DO
    END DO

    DEALLOCATE(mapping)
    CLOSE(1)

    CALL Info( 'LoadGebhardtFactors', '...Done', Level=5 )

    RETURN

10  CONTINUE

    WRITE( Message, * ) 'Can not open file for GebhardtFactors: ',TRIM(FileName)
    CALL Fatal( 'LoadGebhardtFactors', Message )

  END SUBROUTINE LoadGebhardtFactors
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!    Figure out requested coordinate system
!------------------------------------------------------------------------------
  SUBROUTINE SetCoordinateSystem( Model )
!------------------------------------------------------------------------------
     TYPE(Model_t), POINTER :: Model
!------------------------------------------------------------------------------
     LOGICAL :: Found, C(3)
     TYPE(Mesh_t), POINTER :: Mesh
     REAL(KIND=dp) :: x,y,z
     CHARACTER(LEN=MAX_NAME_LEN) :: csys

     csys = ListGetString( Model % Simulation, 'Coordinate System', Found )
     IF ( .NOT. Found ) Csys = 'cartesian'

     IF ( csys=='cartesian' .OR. csys=='polar' ) THEN
        Mesh => Model % Meshes
        x = Mesh % Nodes % x(1)
        y = Mesh % Nodes % y(1)
        z = Mesh % Nodes % z(1)
        c = .FALSE.
        DO WHILE( ASSOCIATED( Mesh ) )
           c(1) = c(1) .OR. ANY( Mesh % Nodes % x /= x )
           c(2) = c(2) .OR. ANY( Mesh % Nodes % y /= y )
           c(3) = c(3) .OR. ANY( Mesh % Nodes % z /= z )
           Mesh => Mesh % Next
        END DO
        Model % DIMENSION = COUNT( c )
     END IF

     SELECT CASE ( csys )
       CASE( 'cartesian' )
         Coordinates = Cartesian
       CASE( 'cartesian 1d' )
         Model % DIMENSION = 1
         Coordinates = Cartesian
       CASE( 'cartesian 2d' )
         Model % DIMENSION = 2
         Coordinates = Cartesian
       CASE( 'cartesian 3d' )
         Model % DIMENSION = 3
         Coordinates = Cartesian
       CASE( 'axi symmetric' )
         Model % DIMENSION = 2
         Coordinates = AxisSymmetric
       CASE( 'cylindric symmetric' )
         Model % DIMENSION = 2
         Coordinates = CylindricSymmetric
       CASE( 'cylindrical' )
         Model % DIMENSION = 3
         Coordinates = Cylindric
       CASE( 'polar' )
         Coordinates = Polar
       CASE( 'polar 2d' )
         Model % DIMENSION = 2
         Coordinates = Polar
       CASE( 'polar 3d' )
         Model % DIMENSION = 3
         Coordinates = Polar
       CASE DEFAULT
         WRITE( Message, * ) 'Unknown global coordinate system: ', TRIM(csys)
         CALL Fatal( 'SetCoordinateSystem', Message )
     END SELECT
!------------------------------------------------------------------------------
   END SUBROUTINE SetCoordinateSystem
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
! Function to read model from the ELMER DATA BASE 
!------------------------------------------------------------------------------
  FUNCTION LoadModel( ModelName,BoundariesOnly,numprocs,mype ) RESULT( Model )
DLLEXPORT LoadModel
!------------------------------------------------------------------------------
    IMPLICIT NONE

    CHARACTER(LEN=*) :: ModelName
    LOGICAL :: BoundariesOnly

    INTEGER, OPTIONAL :: numprocs,mype

    TYPE(Model_t), POINTER :: Model

!------------------------------------------------------------------------------
    TYPE(Mesh_t), POINTER :: Mesh,Mesh1
    INTEGER :: i,j,k,s,nlen
    LOGICAL :: GotIt,found,OneMeshName, OpenFile
    CHARACTER(LEN=MAX_NAME_LEN) :: Name
    CHARACTER(LEN=MAX_NAME_LEN) :: MeshDir,MeshName
!------------------------------------------------------------------------------

    ALLOCATE( Model )
    CurrentModel => Model
    NULLIFY( Model % Variables )

    MeshDir  = ' '
    MeshName = ' '

    Model % DIMENSION = 0
    Model % NumberOfBoundaries = 0
    Model % NumberOfBodies     = 0
    Model % NumberOfICs        = 0
    Model % NumberOfBCs        = 0
    Model % NumberOfEquations  = 0
    Model % NumberOfSolvers    = 0
    Model % NumberOfMaterials  = 0
    Model % NumberOfBodyForces = 0

    INQUIRE( Unit=InFileUnit, OPENED=OpenFile )
    IF ( .NOT. OpenFile ) OPEN( Unit=InFileUnit, File=Modelname, STATUS='OLD' )
    CALL LoadInputFile( Model,InFileUnit,ModelName,MeshDir,MeshName, .TRUE., .TRUE. )
    REWIND( InFileUnit )
    CALL LoadInputFile( Model,InFileUnit,ModelName,MeshDir,MeshName, .TRUE., .FALSE. )
    IF ( .NOT. OpenFile ) CLOSE( InFileUnit )

    Name = ListGetString( Model % Simulation, 'Mesh', GotIt )

    OneMeshName = .FALSE.
    IF ( GotIt ) THEN
      k = 1
      i = 1
      nlen = LEN_TRIM(name)
      DO WHILE( k<=nlen .AND. name(k:k) /= ' ' )
        MeshDir(i:i)  = name(k:k)
        Meshname(i:i) = name(k:k)
        k = k + 1
        i = i + 1
      END DO

      DO WHILE( k<=nlen .AND. Name(k:k) == ' ' )
        k = k + 1
      END DO

      IF ( k<=nlen ) THEN
         MeshName(i:i) = '/'
         i = i + 1
         DO WHILE( name(k:k) /= ' ' )
           MeshName(i:i) = Name(k:k)
           k = k + 1
           i = i + 1
         END DO
      ELSE
         OneMeshName = .TRUE.
         MeshDir = "." // CHAR(0)
      END IF
      MeshName(i:i) = CHAR(0)
    END IF

    NULLIFY( Model % Meshes )
    IF ( MeshDir(1:1) /= ' ' ) THEN
      Model % Meshes => LoadMesh( Model, MeshDir, MeshName, &
              BoundariesOnly, numprocs, mype )

      IF ( OneMeshName ) THEN
         i = 0
      ELSE
         i = LEN_TRIM(MeshName)
         DO WHILE( i>0 .AND. MeshName(i:i) /= '/' )
           i = i-1
         END DO
      END IF

      i = i + 1
      k = 1
      Model % Meshes % Name = ' '
      DO WHILE( MeshName(i:i) /= CHAR(0) )
        Model % Meshes % Name(k:k) = MeshName(i:i)
        k = k + 1
        i = i + 1
      END DO

      DO i=1,Model % NumberOfSolvers
         Model % Solvers(i) % Mesh => Model % Meshes
      END DO
    END IF

    DO s=1,Model % NumberOfSolvers
      Name = ListGetString( Model % Solvers(s) % Values, 'Mesh', GotIt )
      IF ( GotIt ) THEN
        OneMeshName = .FALSE.
        k = 1
        i = 1
        nlen = LEN_TRIM(name)
        DO WHILE( k<=nlen .AND. name(k:k) /= ' ' )
          MeshDir(i:i)  = name(k:k)
          Meshname(i:i) = name(k:k)
          k = k + 1
          i = i + 1
        END DO

        DO WHILE( k<=nlen .AND. Name(k:k) == ' ' )
          k = k + 1
        END DO

        IF ( k<=nlen ) THEN
          MeshName(i:i) = '/'
          i = i + 1
          DO WHILE( name(k:k) /= ' ' )
            MeshName(i:i) = Name(k:k)
            k = k + 1
            i = i + 1
          END DO
        ELSE
          OneMeshName = .TRUE.
          MeshDir = "." // CHAR(0)
        END IF
        MeshName(i:i) = CHAR(0)

        IF ( OneMeshName ) THEN
          i = 0
        ELSE
          DO WHILE( i>0 .AND. MeshName(i:i) /= '/' )
            i = i - 1
          END DO
        END IF

        Mesh => Model % Meshes
        Found = .FALSE.
        DO WHILE( ASSOCIATED( Mesh ) )
           Found = .TRUE.
           k = 1
           j = i+1
           DO WHILE( MeshName(j:j) /= CHAR(0) )
              IF ( Mesh % Name(k:k) /= MeshName(j:j) ) THEN
                Found = .FALSE.
                EXIT
              END IF
              k = k + 1
              j = j + 1
           END DO
           IF ( LEN_TRIM(Mesh % Name) /= k-1 ) Found = .FALSE.
           IF ( Found ) EXIT
           Mesh => Mesh % Next
        END DO

        IF ( Found ) THEN
          Model % Solvers(s) % Mesh => Mesh
          CYCLE
        END IF

        Model % Solvers(s) % Mesh => &
          LoadMesh( Model,MeshDir,MeshName,BoundariesOnly,numprocs,mype )

        IF ( OneMeshName ) i = 0

        k = 1
        i = i + 1
        Model % Solvers(s) % Mesh % Name = ' '
        DO WHILE( MeshName(i:i) /= CHAR(0) )
          Model % Solvers(s) % Mesh % Name(k:k) = MeshName(i:i)
          k = k + 1
          i = i + 1
        END DO

        IF ( ASSOCIATED( Model % Meshes ) ) THEN
          Mesh1 => Model % Meshes
          DO WHILE( ASSOCIATED( Mesh1 % Next ) ) 
            Mesh1 => Mesh1 % Next
          END DO
          Mesh1 % Next => Model % Solvers(s) % Mesh
        ELSE
          Model % Meshes => Model % Solvers(s) % Mesh
        END IF
      END IF
    END DO

    CALL SetCoordinateSystem( Model )
  
    IF ( OutputPath == ' ' ) THEN
      DO i=1,MAX_NAME_LEN
        IF ( MeshDir(i:i) == CHAR(0) ) EXIT
        OutputPath(i:i) = MeshDir(i:i)
      END DO
      OutputPath = TRIM(OutputPath)
    END IF

    Mesh => Model % Meshes
    DO WHILE( ASSOCIATED( Mesh ) )
       CALL MeshStabParams( Mesh )
       Mesh => Mesh % Next
    END DO
!------------------------------------------------------------------------------
  END FUNCTION LoadModel
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  FUNCTION SaveResult( Filename,Mesh,Time,SimulationTime ) RESULT(SaveCount)
DLLEXPORT SaveResult
!------------------------------------------------------------------------------
    TYPE(Mesh_t), POINTER :: Mesh
    INTEGER :: Time,SaveCount
    CHARACTER(LEN=*) :: Filename
    REAL(KIND=dp) :: SimulationTime

!------------------------------------------------------------------------------

    TYPE(Element_t), POINTER :: CurrentElement
    INTEGER :: i,j,k,DOFs, dates(8)
    TYPE(Variable_t), POINTER :: Var
    CHARACTER(LEN=MAX_NAME_LEN) :: FName, DateStr
    LOGICAL :: FreeSurfaceFlag, MoveBoundary, GotIt
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!   If first time here, count number of variables
!------------------------------------------------------------------------------
    FName = FileName
    IF ( INDEX( FileName, ':') == 0 .AND. FileName(1:1) /= '/' .AND. &
             FileName(1:1) /= '\\' ) THEN
      IF ( LEN_TRIM(OutputPath) > 0 ) THEN
        FName = TRIM(OutputPath) // '/' // TRIM(FileName)
      END IF
    END IF

    IF ( Mesh % SavesDone == 0 ) THEN
      OPEN( OutputUnit,File=TRIM(FName),STATUS='UNKNOWN' )
    ELSE
      OPEN( OutputUnit,File=TRIM(FName),STATUS='UNKNOWN', POSITION='APPEND' )
    END IF

    FreeSurfaceFlag = .FALSE.
    MoveBoundary    = .FALSE.
    DO i=1,CurrentModel % NumberOfBCs
      FreeSurfaceFlag = FreeSurfaceFlag .OR. ListGetLogical( &
         CurrentModel % BCs(i) % Values,'Free Surface', GotIt )
      IF ( FreeSurfaceFlag ) THEN
         MoveBoundary =  ListGetLogical( &
             CurrentModel % BCs(i) % Values,'Internal Move Boundary', GotIt )
         
         IF ( .NOT. GotIt ) MoveBoundary = .TRUE.

         FreeSurfaceFlag = FreeSurfaceFlag .AND. MoveBoundary
      END IF

      IF ( FreeSurfaceFlag ) EXIT
    END DO

    IF ( Mesh % SavesDone == 0 ) THEN
      DateStr = FormatDate()
      WRITE( OutputUnit, '("!File started at: ",A)' ) TRIM(DateStr)
      DOFs = 0
      Var => Mesh % Variables
      WRITE( OutputUnit,* ) 'Degrees of freedom: '


      DO WHILE( ASSOCIATED(Var) )
        IF ( Var % Output ) THEN
           IF ( Var % DOFs > 1 .AND. SIZE(Var % Values)>1 ) THEN
             DO k=LEN(Var % Name),1,-1
               IF ( Var % Name(k:k) /= ' ' ) EXIT
             END DO

             IF ( Var % Name(1:10) /= 'coordinate' .OR. FreeSurfaceFlag ) THEN
               WRITE( OutputUnit,* ) Var % Name(1:k),Var % DOFs, &
                  ' :', 'fs' ! TRIM(ListGetString( Var % Solver % Values, 'Equation' ))
             ELSE 
!              WRITE( OutputUnit,* ) Var % Name(1:k),Var % DOFs, &
!              ':eq'
             END IF
           END IF
        END IF

        Var => Var % Next
      END DO 

      Var => Mesh % Variables
      DO WHILE( ASSOCIATED(Var) )
        IF ( Var % Output ) THEN

           IF ( Var % DOFs == 1 .AND. SIZE(Var % Values)>1 ) THEN
             DO k=LEN(Var % Name),1,-1
               IF ( Var % Name(k:k) /= ' ' ) EXIT
             END DO

             IF ( Var % Name(1:10) /= 'coordinate' .OR. FreeSurfaceFlag ) THEN
               WRITE( OutputUnit,* ) Var % Name(1:k),Var % DOFs, &
                ' :', 'fs' ! TRIM(ListGetString( Var % Solver % Values, 'Equation' ))
               IF ( Var % DOFs == 1 ) DOFs = DOFs + 1
             ELSE
!              IF ( Var % DOFs == 1 ) DOFs = DOFs + 1
!              WRITE( OutputUnit,* ) Var % Name(1:k),Var % DOFs, &
!               ':eq'
             END IF
           END IF
        END IF
        Var => Var % Next
      END DO 
      WRITE(OutputUnit,*) 'Total DOFs: ', DOFs
    END IF

    WRITE( OutputUnit,'(a,i7,i7,E20.12E3)' ) 'Time: ', &
        Mesh % SavesDone+1, Time, SimulationTime
!------------------------------------------------------------------------------
!   Write data to disk
!------------------------------------------------------------------------------
    Var => Mesh % Variables
    DO WHILE( ASSOCIATED(Var) )
      IF ( Var % Output ) THEN
         IF ( Var % DOFs==1 .AND. SIZE(Var % Values)>1 ) THEN

           DO k=LEN(Var % Name),1,-1
             IF ( Var % Name(k:k) /= ' ' ) EXIT
           END DO

           IF ( Var % Name(1:10) /= 'coordinate' .OR. FreeSurfaceFlag ) THEN
             WRITE( OutputUnit,'(a)' ) Var % Name(1:k)
   
             DO i=1,Mesh % NumberOfNodes
               k = i
               IF ( ASSOCIATED(Var % Perm) ) k = Var % Perm(k)
!              IF ( k > 0 ) WRITE( OutputUnit,* ) i,k,Var % Values(k)
               IF ( k > 0 ) THEN
                 WRITE( OutputUnit,* ) i,k,Var % Values(k)
               ELSE
                 WRITE( OutputUnit,* ) i,k,0.0d0
               END IF
             END DO
           END IF
         END IF
      END IF
      Var => Var % Next
    END DO 

    CLOSE( OutputUnit )

    Mesh % SavesDone = Mesh % SavesDone + 1
    SaveCount = Mesh % SavesDone 
!------------------------------------------------------------------------------
  END FUNCTION SaveResult
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE LoadRestartFile( RestartFile,TimeCount,Mesh,Continuous )
DLLEXPORT LoadRestartFile
    CHARACTER(LEN=*) :: RestartFile
    INTEGER :: TimeCount
    TYPE(Mesh_T), POINTER :: Mesh
    LOGICAL, OPTIONAL :: Continuous
!------------------------------------------------------------------------------
    TYPE(Variable_t),POINTER :: Var
    CHARACTER(LEN=MAX_NAME_LEN) :: Row,Name
    INTEGER ::i,j,k,n,Node,DOFs,SavedCount,Timestep,NSDOFs

    TYPE(Solver_t),   POINTER :: Solver
    TYPE(Variable_t), POINTER :: TimeVar

    LOGICAL :: RestartFileOpen = .FALSE., Cont

    REAL(KIND=dp) :: Dummy,value,Time
    REAL(KIND=dp), POINTER :: Component(:)
    REAL(KIND=dp), POINTER :: Velocity1(:),Velocity2(:),Velocity3(:),Pressure(:)
!------------------------------------------------------------------------------
!   Open restart file and search for the right position
!------------------------------------------------------------------------------
    CALL Info( 'LoadRestartFile',' ', Level = 3)
    CALL Info( 'LoadRestartFile','---------------------', Level=3 )
    CALL Info( 'LoadRestartFile','Start', Level = 3 )
    CALL Info( 'LoadRestartFile',' ', Level = 3)

    Cont = .FALSE.
    IF ( PRESENT( Continuous ) ) Cont = Continuous

    IF ( Cont .AND. RestartFileOpen ) GOTO 30

    IF ( INDEX( RestartFile, ':') == 0 .AND. RestartFile(1:1) /= '/' &
                .AND. RestartFile(1:1) /= '\\' ) THEN

      IF ( LEN_TRIM(OutputPath) > 0 ) THEN
        OPEN( RestartUnit,File=TRIM(OutputPath) // '/' // TRIM(RestartFile), &
                        STATUS='OLD',ERR=10 )
      ELSE
        OPEN( RestartUnit,File=TRIM(RestartFile),STATUS='OLD',ERR=10 )
      END IF
    ELSE
      OPEN( RestartUnit,File=TRIM(RestartFile),STATUS='OLD',ERR=10 )
    END IF

    GOTO 20

10 CONTINUE

    RETURN

20  CONTINUE

    RestartFileOpen = .TRUE.

    DO WHILE( ReadAndTrim(RestartUnit,Row) )
      IF ( Row(1:18) == 'degrees of freedom' ) EXIT
    END DO

!------------------------------------------------------------------------------
    DO WHILE( ReadAndTrim(RestartUnit,Row) )

      IF ( Row(1:11) == 'total dofs:' ) THEN
        READ( Row(12:),* ) DOFs
        EXIT
      END IF

      k = INDEX(Row,':')

      NULLIFY(Solver)
      DO i = 1,CurrentModel % NumberOfSolvers
        Solver => CurrentModel % Solvers(i)
        IF ( TRIM(Row(k+1:))==ListGetString(Solver % Values, 'Equation')) EXIT
      END DO

      DO j=k-1,1,-1
        IF ( Row(j:j) /= ' ' ) EXIT
      END DO

      DO k=j,1,-1
        IF ( Row(k:k) == ' ' ) EXIT
      END DO

      Var => VariableGet( Mesh % Variables, TRIM(Row(1:k-1)),.TRUE. )

      IF ( .NOT.ASSOCIATED(Var) ) THEN

        READ(Row(k+1:),*) DOFs

        ALLOCATE( Var )
        ALLOCATE( Var % Values(Mesh % NumberOfNodes*DOFs) )
        Var % Values = 0

        ALLOCATE( Var % Perm(Mesh % NumberOfNodes) )
        Var % Perm = -1

        IF ( row(1:14) == 'flow solution ' ) THEN
!------------------------------------------------------------------------------
!         First add components to the variable list separately...
!         (must be done this way for the output routines to work properly...)
!----------------------------------------------------------------------------
          NSDOFs = CoordinateSystemDimension() + 1
          IF ( Coordinates == CylindricSymmetric ) NSDOFs = NSDOFs + 1

          Velocity1 => Var % Values(1:NSDOFs*Mesh % NumberOfNodes:NSDOFs)
          CALL VariableAdd( Mesh % Variables,  Mesh, Solver, 'Velocity 1', &
                       1, Velocity1, Var % Perm )

          Velocity2 => Var % Values(2:NSDOFs*mesh % NumberOfNodes:NSDOFs)
          CALL VariableAdd( Mesh % Variables, Mesh, Solver, 'Velocity 2', &
                       1, Velocity2, Var % Perm )
  
          IF ( NSDOFs == 3 ) THEN
            Pressure => Var % Values(3:NSDOFs*Mesh % NumberOfNodes:NSDOFs)
            CALL VariableAdd( Mesh % Variables, Mesh, Solver, 'Pressure', &
                       1, Pressure, Var % Perm )
          ELSE
            Velocity3 => Var % Values(3:NSDOFs*Mesh % NumberOfNodes:NSDOFs)
            CALL VariableAdd( Mesh % Variables, Mesh, Solver, 'Velocity 3', &
                       1, Velocity3, Var % Perm )

            Pressure => Var % Values(4:NSDOFs*Mesh % NumberOfNodes:NSDOFs)
             CALL VariableAdd( Mesh % Variables, Mesh, Solver, 'Pressure', &
                         1, Pressure, Var % Perm )
           END IF
!------------------------------------------------------------------------------
!        Then add the thing itself
!------------------------------------------------------------------------------
         CALL VariableAdd( Mesh % Variables, Mesh, Solver, &
                'Flow Solution',NSDOFs,Var % Values,Var % Perm )
        ELSE
          IF ( DOFs > 1 ) THEN
            DO i=1,DOFs
              Component => Var % Values(i:DOFs*Mesh % NumberOfNodes:DOFs)
              name = ComponentName( TRIM(row(1:k-1)), i )
              CALL VariableAdd( Mesh % Variables,  Mesh, Solver, TRIM(name), &
                           1, Component, Var % Perm )
            END DO
          END IF
          CALL VariableAdd( Mesh % Variables, Mesh, Solver, &
              Row(1:k-1),DOFs,Var % Values,Var % Perm )
        END IF
      END IF
    END DO

30  CONTINUE

!------------------------------------------------------------------------------
!   ...read one timestep to memory...
!------------------------------------------------------------------------------
    TimeVar => VariableGet( Mesh % Variables, 'Time' )
    n = 1
    IF ( Cont ) n = TimeCount
    DO WHILE( n <= TimeCount .OR. TimeCount == 0 )
      DO WHILE( ReadAndTrim(RestartUnit,Row) )
        IF ( Row(1:5) == 'time:' ) EXIT
      END DO

      IF ( Row(1:5) /= 'time:' ) THEN
        IF ( TimeCount /= 0 ) THEN
          CALL Warn( 'LoadRestartFile','Did not find the the requested' )
          CALL Warn( 'LoadRestartFile','restart position from the restart file, using the last' )
          CALL Warn( 'LoadRestartFile','data found.' )
        END IF
        EXIT
      END IF

      READ( Row(7:),* ) SavedCount,Timestep,Time
      IF ( ASSOCIATED( TimeVar ) ) TimeVar % Values(1) = Time

      DO i=1,DOFs
        READ( RestartUnit,'(a)' ) Row
        Var => VariableGet( Mesh % Variables,TRIM(Row) )

        IF ( ASSOCIATED(Var) ) THEN
          DO j=1,Mesh % NumberOfNodes
            READ(RestartUnit,*) Node,k,value

            IF ( .NOT. ASSOCIATED( Var % Perm ) ) THEN
               IF ( k >= 0 ) Var % Values(k) = value
            ELSE IF ( Var % Perm(j) < 0 ) THEN
               Var % Perm(j) = k
               IF ( k > 0 ) Var % Values(k) = value
            ELSE IF ( Var % Perm(j)>0 ) THEN
               IF ( k > 0 ) Var % Values(Var % Perm(j)) = value
            END IF
          END DO
        END IF
      END DO
      n = n + 1
    END DO
!------------------------------------------------------------------------------
    IF ( .NOT. Cont ) THEN
       CLOSE(RestartUnit)
       RestartFileOpen = .FALSE.
    END IF
    CALL Info( 'LoadRestartFile', 'Done', Level=3 )
    CALL Info( 'LoadRestartFile', '---------------------', Level = 3)
    CALL Info( 'LoadRestartFile', ' ', Level = 3 )
  END SUBROUTINE LoadRestartFile
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE WritePostFile( PostFile,ResultFile,Model,TimeCount,AppendFlag )
DLLEXPORT WritePostFile
!------------------------------------------------------------------------------
    TYPE(Model_t), POINTER :: Model 
    INTEGER :: TimeCount
    LOGICAL, OPTIONAL :: AppendFlag
    CHARACTER(LEN=*) :: PostFile,ResultFile
!------------------------------------------------------------------------------
    TYPE(Element_t), POINTER :: CurrentElement
    TYPE(Variable_t), POINTER :: Var,Var1,Displacement,MeshUpdate

    CHARACTER(LEN=512) :: Row
    CHARACTER(MAX_NAME_LEN) :: Str, DateStr

    LOGICAL :: gotIt, FreeSurfaceFlag, MoveBoundary

    REAL(KIND=dp) :: Time,Dummy
    INTEGER :: i,j,k,l,n,Node,idummy,DOFs,SavedCount,TimeStep
!------------------------------------------------------------------------------

    IF ( INDEX( PostFile, ':') == 0 .AND. PostFile(1:1) /= '/' .AND. &
             PostFile(1:1) /= '\\' ) THEN

      IF ( LEN_TRIM(OutputPath) > 0 ) THEN
        IF ( AppendFlag .AND. Model % Mesh % SavesDone /= 0 )  THEN
          OPEN( PostFileUnit,File=TRIM(OutputPath) // '/' // &
             TRIM(PostFile), POSITION='APPEND' )
        ELSE
          OPEN( PostFileUnit,File=TRIM(OutputPath) // '/' // &
             TRIM(PostFile),STATUS='UNKNOWN' )
        END IF
      ELSE
        IF ( AppendFlag .AND. Model % Mesh % SavesDone /= 0 ) THEN
          OPEN( PostFileUnit,File=TRIM(PostFile),POSITION='APPEND' )
        ELSE
          OPEN( PostFileUnit,File=TRIM(PostFile),STATUS='UNKNOWN' )
        ENDIF
      END IF
    ELSE
      IF ( AppendFlag .AND. Model % Mesh % SavesDone /= 0  ) THEN
        OPEN( PostFileUnit,File=TRIM(PostFile),POSITION='APPEND' )
      ELSE
        OPEN( PostFileUnit,File=TRIM(PostFile),STATUS='UNKNOWN' )
      END IF
    END IF

    IF ( .NOT.AppendFlag ) THEN
      IF ( INDEX( ResultFile, ':') == 0 .AND. ResultFile(1:1) /= '/' .AND. &
               ResultFile(1:1) /= '\\' ) THEN
        IF ( LEN_TRIM(OutputPath) > 0 ) THEN
          OPEN( OutputUnit,File=TRIM(OutputPath) // '/' &
              // TRIM(ResultFile),STATUS='OLD' )
        ELSE
          OPEN( OutputUnit,File=TRIM(ResultFile),STATUS='OLD' )
        END IF
      ELSE
        OPEN( OutputUnit,File=TRIM(ResultFile),STATUS='OLD' )
      END IF
    END IF

    FreeSurfaceFlag = .FALSE.
    MoveBoundary    = .FALSE.
    DO i=1,CurrentModel % NumberOfBCs
      FreeSurfaceFlag = FreeSurfaceFlag .OR. ListGetLogical( &
         CurrentModel % BCs(i) % Values,'Free Surface', GotIt )
      IF ( FreeSurfaceFlag ) THEN
         MoveBoundary =  ListGetLogical( &
             CurrentModel % BCs(i) % Values,'Internal Move Boundary', GotIt )
         
         IF ( .NOT. GotIt ) MoveBoundary = .TRUE.

         FreeSurfaceFlag = FreeSurfaceFlag .AND. MoveBoundary
      END IF

      IF ( FreeSurfaceFlag ) EXIT
    END DO

!------------------------------------------------------------------------------
!   Count degrees of freedom to be saved
!------------------------------------------------------------------------------
    DOFs = 0
    Var => Model % Variables
    DO WHILE( ASSOCIATED( Var ) )
      IF ( .NOT. Var % Output ) THEN
         Var => Var % Next
         CYCLE
      END IF

      SELECT CASE(Var % Name)
        CASE('time')

        CASE( 'mesh update' )
           Var1 => Model % Variables
           DO WHILE( ASSOCIATED( Var1 ) )
             IF ( TRIM(Var1 % Name) == 'displacement' ) EXIT
             Var1 => Var1 % Next
           END DO
           IF ( .NOT. ASSOCIATED( Var1 ) ) THEN
              DOFs = DOFs + 3
           END IF

        CASE('mesh update 1','mesh update 2', 'mesh update 3' )

        CASE( 'displacement' )
          DOFs = DOFs + 3

        CASE( 'displacement 1','displacement 2','displacement 3')

        CASE( 'flow solution' )
          DOFs = DOFs + 4

        CASE( 'velocity 1','velocity 2','velocity 3','pressure' )

        CASE( 'magnetic field' )
          DOFs = DOFs + 3

        CASE( 'magnetic field 1','magnetic field 2','magnetic field 3')

        CASE( 'electric current' )
          DOFs = DOFs + 3

        CASE( 'electric current 1','electric current 2','electric current 3')

        CASE( 'magnetic flux density' )
          DOFs = DOFs + 3

        CASE( 'magnetic flux density 1','magnetic flux density 2','magnetic flux density 3')

        CASE DEFAULT
          IF ( Var % DOFs == 1 ) DOFs = DOFs + 1
      END SELECT
      Var => Var % Next
    END DO

    IF ( .NOT.FreeSurfaceFlag ) DOFs = DOFs - 3

!------------------------------------------------------------------------------
! Write header to output
!------------------------------------------------------------------------------
    IF ( .NOT.AppendFlag .OR. Model % Mesh % SavesDone == 0 ) THEN
      WRITE(PostFileUnit,'(i10,i10,i7,i7)',ADVANCE='NO' ) Model % NumberOfNodes, &
       Model % NumberOfBulkElements+ Model % NumberOfBoundaryElements, &
          DOFs,TimeCount

      NULLIFY( Displacement, MeshUpdate )

      Var => Model % Variables
      DO WHILE( ASSOCIATED( Var ) )

        IF ( .NOT. Var % Output ) THEN
           Var => Var % Next
           CYCLE
        END IF

        SELECT CASE(Var % Name)
          CASE('time')

          CASE( 'mesh update' )

             Var1 => Model % Variables
             DO WHILE( ASSOCIATED( Var1 ) )
               IF ( TRIM(Var1 % Name) == 'displacement' ) EXIT
               Var1 => Var1 % Next
             END DO

             IF ( .NOT. ASSOCIATED( Var1 ) ) THEN
                WRITE(PostFileUnit,'(a)',ADVANCE='NO') ' vector: Mesh.Update'
                Displacement => Var
             ELSE
                MeshUpdate   => Var
             END IF

          CASE( 'mesh update 1','mesh update 2', 'mesh update 3' )

          CASE( 'displacement' )
            WRITE(PostFileUnit,'(a)',ADVANCE='NO' ) ' vector: Displacement'
            Displacement => Var

          CASE( 'displacement 1','displacement 2','displacement 3')

          CASE( 'flow solution' )
            WRITE(PostFileUnit,'(a)',ADVANCE='NO') ' vector: Velocity scalar: Pressure'

          CASE( 'velocity 1','velocity 2','velocity 3','pressure' )

          CASE( 'magnetic field' )
            WRITE(PostFileUnit,'(a)',ADVANCE='NO' ) ' vector: MagField'

          CASE( 'magnetic field 1','magnetic field 2','magnetic field 3')

          CASE( 'electric current' )
            WRITE(PostFileUNit,'(a)',ADVANCE='NO' ) ' vector: Current'

          CASE( 'electric current 1','electric current 2','electric current 3')

          CASE( 'magnetic flux density' )
            WRITE(PostFileUnit,'(a)',ADVANCE='NO' ) ' vector: MagneticFlux'

          CASE( 'magnetic flux density 1','magnetic flux density 2','magnetic flux density 3')

          CASE( 'coordinate 1','coordinate 2','coordinate 3' )

          CASE DEFAULT
            IF ( Var % DOFs == 1 ) THEN
              DO i=1,Var % NameLen
                str(i:i) = Var % Name(i:i)
                IF ( str(i:i) == ' ' ) str(i:i) = '.'
              END DO
              str(1:1) = CHAR(ICHAR(str(1:1))-ICHAR('a')+ICHAR('A'))
  
              WRITE(PostFileUnit,'(a,a)',ADVANCE='NO' ) ' scalar: ',str(1:Var % NameLen)
            END IF
        END SELECT
        Var => Var % Next
      END DO

      IF ( FreeSurfaceFlag ) THEN
        WRITE(PostFileUnit,'(a)',ADVANCE='NO' ) ' vector: Coordinates'
      END IF

      WRITE(PostFileUnit,'()')
      DateStr = FormatDate()
      WRITE( PostFileUnit, '("#File started at: ",A)' ) TRIM(DateStr)
!------------------------------------------------------------------------------
!   Coordinates
!------------------------------------------------------------------------------
!
      DO i=1,Model % NumberOfNodes
         IF ( ASSOCIATED(Displacement) ) THEN
            k = Displacement % Perm(i)
            l = 0
            IF ( ASSOCIATED( MeshUpdate ) ) l = MeshUpdate % Perm(i)

            IF ( k > 0 ) THEN
               k = Displacement % DOFs * (k-1)
               SELECT CASE( Displacement % DOFs )
                  CASE(1)
                     WRITE(PostFileUnit,'(3E20.12E3)') &
                          Model % Nodes % x(i) - Displacement % Values(k+1), &
                             Model % Nodes % y(i), Model % Nodes % z(i)

                  CASE(2)
                     WRITE(PostFileUnit,'(3E20.12E3)') &
                          Model % Nodes % x(i) - Displacement % Values(k+1), &
                          Model % Nodes % y(i) - Displacement % Values(k+2), &
                          Model % Nodes % z(i)

                  CASE(3)
                     WRITE(PostFileUnit,'(3E20.12E3)') &
                          Model % Nodes % x(i) - Displacement % Values(k+1), &
                          Model % Nodes % y(i) - Displacement % Values(k+2), &
                          Model % Nodes % z(i) - Displacement % Values(k+3)
               END SELECT
            ELSE IF ( l > 0 ) THEN
               k = MeshUpdate % DOFs * (l-1)
               SELECT CASE( MeshUpdate % DOFs )
                  CASE(1)
                     WRITE(PostFileUnit,'(3E20.12E3)') &
                          Model % Nodes % x(i) - MeshUpdate % Values(k+1), &
                             Model % Nodes % y(i), Model % Nodes % z(i)

                  CASE(2)
                     WRITE(PostFileUnit,'(3E20.12E3)') &
                          Model % Nodes % x(i) - MeshUpdate % Values(k+1), &
                          Model % Nodes % y(i) - MeshUpdate % Values(k+2), &
                          Model % Nodes % z(i)

                  CASE(3)
                     WRITE(PostFileUnit,'(3E20.12E3)') &
                          Model % Nodes % x(i) - MeshUpdate % Values(k+1), &
                          Model % Nodes % y(i) - MeshUpdate % Values(k+2), &
                          Model % Nodes % z(i) - MeshUpdate % Values(k+3)
               END SELECT
            ELSE
             WRITE(PostFileUnit,'(3E20.12E3)') Model % Nodes % x(i),Model % Nodes % y(i), &
                               Model % Nodes % z(i)
            ENDIF
         ELSE
             WRITE(PostFileUnit,'(3E20.12E3)') Model % Nodes % x(i),Model % Nodes % y(i), &
                               Model % Nodes % z(i)
         END IF
      END DO

!------------------------------------------------------------------------------
! Elements
!------------------------------------------------------------------------------
      WRITE(PostFileUnit,'(a)') '#group all'
      DO i=1,Model % NumberOfBulkElements
        CurrentElement => Model % Elements(i)
        k = CurrentElement % BodyId

        gotIt = .FALSE.
        IF ( k >= 1 .AND. k <= Model % NumberOfBodies ) THEN
          Str = ListGetString( Model % Bodies(k) % Values,'Name',gotIt )
        END IF

        IF ( gotIt ) THEN
          k = LEN_TRIM(Str)
          DO j=1,k
             IF ( Str(j:j) == ' ' ) Str(j:j) = '.'
          END DO

          WRITE( PostFileUnit,'(a)',ADVANCE='NO' )  Str(1:k)
        ELSE
          IF ( k > 0 .AND. k < 10 ) THEN
            WRITE(PostFileUnit,'(a,i1,a)',ADVANCE='NO' ) 'body',k,' '
          ELSE IF ( k >= 10 .AND. k < 100 ) THEN
            WRITE(PostFileUnit,'(a,i2,a)',ADVANCE='NO' ) 'body',k,' '
          ELSE
            WRITE(PostFileUnit,'(a,i3,a)',ADVANCE='NO' ) 'body',k,' '
          END IF
        END IF

        WRITE(PostFileUnit,'(i5)', ADVANCE='NO') CurrentElement % TYPE % ElementCode
        n = 0
        DO j=1,CurrentElement % TYPE % NumberOfNodes,4
          DO k=1,MIN(4,CurrentElement % TYPE % NumberOfNodes-n)
            n = n + 1
            WRITE(PostFileUnit, '(i8)', ADVANCE='NO')  CurrentElement % NodeIndexes(n)-1
          END DO
          WRITE( PostFileUnit,'(a)' ) ''
        END DO
      END DO

      DO i=Model % NumberOfBulkElements + 1,Model % NumberOfBulkElements + &
                     Model % NumberOfBoundaryElements

        CurrentElement => Model % Elements(i)

        k = CurrentElement % BoundaryInfo % Constraint

        gotIt = .FALSE.
        IF ( k >= 1 .AND. k <= Model % NumberOfBCs ) THEN
          Str = ListGetString( Model % BCs(k) % Values,'Name',gotIt )
        END IF

        IF ( gotIt ) THEN
          k = LEN_TRIM(Str)
          DO j=1,k
             IF ( Str(j:j) == ' ' ) Str(j:j) = '.'
          END DO

          WRITE( PostFileUnit,'(a)',ADVANCE='NO' )  Str(1:k)
        ELSE
          IF ( k < 10 ) THEN
            WRITE( PostFileUnit,'(a,i1,a)',ADVANCE='NO' ) 'Constraint', k, ' '
          ELSE IF ( k < 100 ) THEN
            WRITE( PostFileUnit,'(a,i2,a)',ADVANCE='NO' ) 'Constraint', k, ' '
          ELSE
            WRITE( PostFileUnit,'(a,i3,a)',ADVANCE='NO' ) 'Constraint', k, ' '
          END IF
        END IF

        WRITE(PostFileUnit,'(i5)', ADVANCE='NO') CurrentElement % TYPE % ElementCode
        DO k=1,CurrentElement % TYPE % NumberOfNodes
          WRITE( PostFileUnit, '(i8)', ADVANCE='NO' )  CurrentElement % NodeIndexes(k)-1
        END DO
        WRITE( PostFileUnit,'(a)' ) ''
      END DO
      WRITE(PostFileUnit,'(a)') '#endgroup all'
!------------------------------------------------------------------------------
!   Open result file and go trough it...
!------------------------------------------------------------------------------

      REWIND(OutputUnit)
    END IF ! .NOT.AppendFlag .OR. Model % Mesh % SavesDone == 0

    IF ( AppendFlag .AND. Model % Mesh % SavesDone == 0 ) THEN
      CLOSE(PostFileUnit)
      RETURN
    END IF

!------------------------------------------------------------------------------
    DO WHILE( .TRUE. )
      IF ( AppendFlag ) THEN
        SavedCount = Model % Mesh % SavesDone
        TimeStep   = SavedCount
        Var => VariableGet( Model % Variables, 'Time' )        
        Time = 1.0d0
        IF ( ASSOCIATED(Var) ) Time = Var % Values(1)
      ELSE
!------------------------------------------------------------------------------
!   ...read one timestep to memory (if not already there)...
!------------------------------------------------------------------------------
        Row = ' '
        DO WHILE( ReadAndTrim(OutputUnit,Row) )
          IF ( Row(1:11) == 'total dofs:' ) READ( Row(12:),* ) DOFs
          IF ( Row(1:5)  == 'time:' ) EXIT
        END DO

        IF ( Row(1:5) /= 'time:' ) EXIT

        READ( Row(7:),* ) SavedCount,Timestep,Time
      END IF

      WRITE( PostFileUnit,'(a,i7,i7,E20.12E3)' ) '#time ',SavedCount,Timestep,Time

      IF ( .NOT.AppendFlag ) THEN
        DO i=1,DOFs
          READ(OutputUnit,'(a)' ) Row
          Var => VariableGet( Model % Variables,Row,.TRUE. )
  
          IF ( ASSOCIATED(Var) ) THEN
            DO j=1,Model % NumberOfNodes
              k = j
              IF ( ASSOCIATED(Var % Perm) ) k = Var % Perm(k)
              IF ( k > 0 ) THEN
                READ(OutputUnit,*) Node,idummy,Var % Values(k)
              ELSE
                READ(OutputUnit,*) Node,idummy,Dummy
              END IF
            END DO
          END IF
        END DO
      END IF
!-----------------------------------------------------------------------------
!     ...then save it to post file.
!------------------------------------------------------------------------------
      DO i=1,Model % NumberOfNodes

        Var => Model % Variables
        DO WHILE( ASSOCIATED( Var ) )
          IF ( .NOT. Var % Output ) THEN
             Var => Var % Next
             CYCLE
          END IF

          SELECT CASE(Var % Name)
            CASE('time')

            CASE( 'mesh update' )
               Var1 => Model % Variables
               DO WHILE( ASSOCIATED( Var1 ) )
                 IF ( TRIM(Var1 % Name) == 'displacement' ) EXIT
                 Var1 => Var1 % Next
               END DO
               IF ( .NOT. ASSOCIATED( Var1 ) ) THEN
                  k = i
                  IF ( ASSOCIATED(Var % Perm) ) k = Var % Perm(k)
                  IF ( k > 0 ) THEN
                     DO j=1,Var % DOFs
                       WRITE(PostFileUnit,'(E20.12E3)',ADVANCE='NO') Var % Values(Var % DOFs*(k-1)+j)
                     END DO
                     IF ( Var % DOFs < 3 ) WRITE(PostFileUnit,'(E20.12E3)',ADVANCE='NO') 0.0D0
                  ELSE
                    WRITE(PostFileUnit,'(4E20.12E3)',ADVANCE='NO') 0.0D0,0.0D0,0.0D0
                  END IF
               END IF

            CASE(  'mesh update 1','mesh update 2', 'mesh update 3' )

            CASE( 'displacement' )
              k = i
              IF ( ASSOCIATED(Var % Perm) ) k = Var % Perm(k)

              IF ( k > 0 ) THEN
                DO j=1,Var % DOFs
                  WRITE(PostFileUnit,'(E20.12E3)',ADVANCE='NO') Var % Values(Var % DOFs*(k-1)+j)
                END DO
                IF ( Var % DOFs < 3 ) WRITE(PostFileUnit,'(E20.12E3)',ADVANCE='NO') 0.0D0
              ELSE
                Var1 => Model % Variables
                DO WHILE( ASSOCIATED( Var1 ) )
                  IF ( TRIM(Var1 % Name) == 'mesh update' ) EXIT
                  Var1 => Var1 % Next
                END DO
                IF ( ASSOCIATED( Var1 ) ) THEN
                  k = i
                  IF ( ASSOCIATED(Var1 % Perm) ) k = Var1 % Perm(k)
                  IF ( k > 0 ) THEN
                    DO j=1,Var1 % DOFs
                      WRITE(PostFileUnit,'(E20.12E3)',ADVANCE='NO')  &
                          Var1 % Values(Var1 % DOFs*(k-1)+j)
                    END DO
                    IF ( Var1 % DOFs<3 ) &
                      WRITE(PostFileUnit,'(E20.12E3)',ADVANCE='NO') 0.0D0
                  ELSE
                    WRITE(PostFileUnit,'(4E20.12E3)',ADVANCE='NO') 0.0D0,0.0D0,0.0D0
                  END IF
                ELSE
                  WRITE(PostFileUnit,'(4E20.12E3)',ADVANCE='NO') 0.0D0,0.0D0,0.0D0
                END IF
              END IF

            CASE( 'displacement 1','displacement 2','displacement 3')

            CASE( 'flow solution' )
              k = i
              IF ( ASSOCIATED(Var % Perm) ) k = Var % Perm(k)
              IF ( k > 0 ) THEN
                DO j=1,Var % DOFs-1
                  WRITE(PostFileUnit,'(E20.12E3)',ADVANCE='NO') Var % Values(Var % DOFs*(k-1)+j)
                END DO
                IF ( Var % DOFs < 4 ) WRITE(PostFileUnit,'(E20.12E3)',ADVANCE='NO') 0.0D0

                WRITE(PostFileUnit,'(E20.12E3)',ADVANCE='NO')  &
                           Var % Values(Var % DOFs*(k-1)+Var % DOFs)
              ELSE
                WRITE(PostFileUnit,'(4E20.12E3)',ADVANCE='NO') 0.0D0,0.0D0,0.0D0,0.0D0
              END IF

            CASE( 'velocity 1','velocity 2','velocity 3','pressure' )

            CASE( 'magnetic field' )
              k = i
              IF ( ASSOCIATED(Var % Perm) ) k = Var % Perm(k)
              IF ( k > 0 ) THEN
                DO j=1,Var % DOFs
                  WRITE(PostFileUnit,'(E20.12E3)',ADVANCE='NO') Var % Values(Var % DOFs*(k-1)+j)
                END DO
                IF ( Var % DOFs < 3 ) WRITE(PostFileUnit,'(E20.12E3)',ADVANCE='NO') 0.0D0
              ELSE
                WRITE(PostFileUnit,'(4E20.12E3)',ADVANCE='NO') 0.0D0,0.0D0,0.0D0
              END IF

            CASE( 'magnetic field 1','magnetic field 2','magnetic field 3')

            CASE( 'electric current' )
               k = i
               IF ( ASSOCIATED(Var % Perm) ) k = Var % Perm(k)
               IF ( k > 0 ) THEN
                 DO j=1,Var % DOFs
                   WRITE(PostFileUnit,'(E20.12E3)',ADVANCE='NO') Var % Values(Var % DOFs*(k-1)+j)
                 END DO
                 IF ( Var % DOFs < 3 ) WRITE(PostFileUnit,'(E20.12E3)',ADVANCE='NO') 0.0D0
               ELSE
                 WRITE(PostFileUnit,'(4E20.12E3)',ADVANCE='NO') 0.0D0,0.0D0,0.0D0
               END IF

            CASE( 'electric current 1','electric current 2','electric current 3')

            CASE( 'coordinate 1','coordinate 2','coordinate 3' )

            CASE( 'magnetic flux density' )
              k = i
              IF ( ASSOCIATED(Var % Perm) ) k = Var % Perm(k)
              IF ( k > 0 ) THEN
                DO j=1,Var % DOFs
                  WRITE(PostFileUnit,'(E20.12E3)',ADVANCE='NO') Var % Values(Var % DOFs*(k-1)+j)
                END DO
                IF ( Var % DOFs < 3 ) WRITE(PostFileUnit,'(E20.12E3)',ADVANCE='NO') 0.0D0
              ELSE
                WRITE(PostFileUnit,'(4E20.12E3)',ADVANCE='NO') 0.0D0,0.0D0,0.0D0
              END IF

            CASE( 'magnetic flux density 1','magnetic flux density 2','magnetic flux density 3')

            CASE DEFAULT
              IF ( Var % DOFs == 1 ) THEN
                k = i
                IF ( ASSOCIATED(Var % Perm) ) k = Var % Perm(k)
                IF ( k > 0 ) THEN
                  WRITE(PostFileUnit,'(E20.12E3)',ADVANCE='NO') Var % Values(k)
                ELSE
                  WRITE(PostFileUnit,'(E20.12E3)',ADVANCE='NO') 0.0D0
                END IF
              END IF
          END SELECT
          Var => Var % Next
        END DO

        IF ( FreeSurfaceFlag ) THEN
          Var => VariableGet( Model % Variables,'Coordinate 1' )
          WRITE(PostFileUnit,'(E20.12E3)',ADVANCE='NO') Var % Values(i)

          Var => VariableGet( Model % Variables,'Coordinate 2' )
          WRITE(PostFileUnit,'(E20.12E3)',ADVANCE='NO') Var % Values(i)

          Var => VariableGet( Model % Variables,'Coordinate 3' )
          WRITE(PostFileUnit,'(E20.12E3)',ADVANCE='NO') Var % Values(i)
        END IF

        WRITE(PostFileUnit,'()')
      END DO
      IF (  AppendFlag ) EXIT
!------------------------------------------------------------------------------
    END DO
!------------------------------------------------------------------------------
!   We are done here close the files...
!------------------------------------------------------------------------------
    CLOSE(PostFileUnit)
    IF ( .NOT. AppendFlag ) CLOSE(OutputUnit)

  END SUBROUTINE WritePostFile
!------------------------------------------------------------------------------

END MODULE ModelDescription
