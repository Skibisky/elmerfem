!/******************************************************************************
! *
! *       ELMER, A Computational Fluid Dynamics Program.
! *
! *       Copyright 1st April 1995 - , Center for Scientific Computing,
! *                                    Finland.
! *
! *       All rights reserved. No part of this program may be used,
! *       reproduced or transmitted in any form or by nay means
! *       without the written permission of CSC.
! *
! *****************************************************************************/
!
!/******************************************************************************
! *
! *  Module computing Navier-Stokes local matrices (cartesian coordinates)
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
! *                Modified by:
! *
! *       Date of modification:
! *
! * $Log: NavierStokes.f90,v $
! * Revision 1.63  2005/04/21 06:44:45  jpr
! * *** empty log message ***
! *
! * Revision 1.62  2005/04/04 06:18:30  jpr
! * *** empty log message ***
! *
! * Revision 1.61  2005/04/01 07:12:32  jpr
! * *** empty log message ***
! *
! * Revision 1.60  2004/09/24 12:15:32  jpr
! * Some corrections to the previous edits.
! *
! * Revision 1.59  2004/09/23 12:31:07  jpr
! * Added user defined compressibility model.
! *
! * Revision 1.58  2004/08/10 13:54:15  raback
! * Added external force of type f \grad g where f and g are given fields
! *
! * Revision 1.53  2004/06/03 15:59:00  raback
! * Added ortotropic porous media (i.e. Darcys law).
! *
! * Revision 1.49  2004/03/24 11:14:18  jpr
! * Added divergence form discretization of the diffusion term.
! *
! *
! * $Id: NavierStokes.f90,v 1.63 2005/04/21 06:44:45 jpr Exp $
! *****************************************************************************/

MODULE NavierStokes

  USE Integration
  USE Differentials
  USE MaterialModels

  IMPLICIT NONE

  CONTAINS

!------------------------------------------------------------------------------
   SUBROUTINE NavierStokesCompose  (                                            &
       MassMatrix, StiffMatrix, ForceVector, LoadVector, NodalViscosity,        &
       NodalDensity, Ux, Uy, Uz, MUx, MUy, MUz, NodalPressure, NodalTemperature,&
       Convect, StabilizeFlag, Compressible1, Compressible2,                    &
       PseudoCompressible, NodalCompressibility, Porous, NodalDrag,             &
       PotentialForce, PotentialField, PotentialCoefficient,                    &
       DivDiscretization,  gradPDiscretization, NewtonLinearization,            &
       Element, n, Nodes )
DLLEXPORT NavierStokesCompose
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Return element local matrices and RSH vector for Navier-Stokes-Equations
!
!  ARGUMENTS:
!
!  REAL(KIND=dp) :: MassMatrix(:,:)
!     OUTPUT: time derivative coefficient matrix
!
!  REAL(KIND=dp) :: StiffMatrix(:,:)
!     OUTPUT: rest of the equation coefficients
!
!  REAL(KIND=dp) :: ForceVector(:)
!     OUTPUT: RHS vector
!
!  REAL(KIND=dp) :: LoadVector(:)
!     INPUT:
!
!  REAL(KIND=dp) :: NodalViscosity(:)
!     INPUT: Nodal values for viscosity (i.e. if turbulence model or
!             power-law viscosity is used, the values vary in space)
!
!  REAL(KIND=dp) :: NodalDensity(:)
!     INPUT: Nodal values of density
!
!  REAL(KIND=dp) :: Ux(:),Uy(:),Uz(:)
!     INPUT: Nodal values of velocity components from previous iteration
!
!  REAL(KIND=dp) :: NodalPressure(:)
!     INPUT: Nodal values of total pressure from previous iteration
!
!  LOGICAL :: Stabilize
!     INPUT: Should stabilization be used ?
!
!  LOGICAL :: Compressible1, Compressible2
!     INPUT: Should compressible flow terms be added ?
!
!  LOGICAL :: PseudoCompressible
!     INPUT: Should artificial compressibility be added ?
!
!  REAL(KIND=dp) :: NodalCompressibility(:)
!     INPUT: Artificial compressibility for the nodes
!
!  LOGICAL :: NewtonLinearization
!      INPUT: Picard or Newton linearization of the convetion term ?
!
!  TYPE(Element_t) :: Element
!       INPUT: Structure describing the element (dimension,nof nodes,
!               interpolation degree, etc...)
!
!  INTEGER :: n
!       INPUT: Number of element nodes
!
!  TYPE(Nodes_t) :: Nodes
!       INPUT: Element node coordinates
!
!******************************************************************************
!------------------------------------------------------------------------------

     REAL(KIND=dp),TARGET :: MassMatrix(:,:),StiffMatrix(:,:),ForceVector(:)
     REAL(KIND=dp), DIMENSION(:) :: Ux,Uy,Uz,MUx,MUy,MUz
     LOGICAL :: StabilizeFlag, Compressible1, Compressible2, PseudoCompressible, Porous, &
         NewtonLinearization, Convect, DivDiscretization, gradPDiscretization, &
         PotentialForce
     REAL(KIND=dp) :: NodalViscosity(:),NodalDensity(:), &
       NodalPressure(:), LoadVector(:,:), NodalTemperature(:), &
       NodalCompressibility(:), NodalDrag(:,:), PotentialField(:), &
       PotentialCoefficient(:)

     INTEGER :: n

     TYPE(Nodes_t) :: Nodes
     TYPE(Element_t), POINTER :: Element

     REAL(KIND=dp) :: LES(6,6,n)
     TYPE(Variable_t), POINTER :: LESVar
!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
     REAL(KIND=dp) :: Basis(2*n),dBasisdx(2*n,3),ddBasisddx(n,3,3)
     REAL(KIND=dp) :: SqrtElementMetric, NodalBasis(n), dLBasisdx(n,3)

     REAL(KIND=dp) :: Velo(3),dVelodx(3,3),Force(4),Metric(3,3),Symb(3,3,3), Drag(3)

     REAL(KIND=dp), POINTER :: A(:,:),M(:,:),Load(:)
     REAL(KIND=dp) :: SU(n,4,4),SW(n,4,4),LrF(3), LSx(3,3)

     REAL(KIND=dp) :: Lambda=1.0,Re,Tau,Delta,Re1,Re2
     REAL(KIND=dp) :: VNorm,hK,mK,Viscosity,dViscositydx(3),Temperature
     REAL(KIND=dp) :: dDensitydx(3), Density, Pressure, dTemperaturedx(3), &
                      dPressuredx(3),dPrevPressuredx(3), Compress

     INTEGER :: i,j,k,l,c,p,q,t,dim

     REAL(KIND=dp) :: s,u,v,w,volume
  
     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff
     INTEGER :: N_Integ, NBasis, deg(100)
     REAL(KIND=dp), DIMENSION(:), POINTER :: U_Integ,V_Integ,W_Integ,S_Integ

     LOGICAL :: stat, Bubbles, PBubbles, Stabilize
!------------------------------------------------------------------------------

     dim = CoordinateSystemDimension()

!#ifdef LES
!     LESVar => VariableGet( CurrentModel % Variables, 'LES' )
!     IF ( ASSOCIATED( LESVar ) ) THEN
!        k = 0
!        DO i=1,dim
!        DO j=i,dim
!           k = k + 1
!           LES(i,j,1:n) = LESVar % Values( LESVar % DOFs*(LESVar % Perm( &
!                       Element % NodeIndexes)-1)+k )
!        END DO
!        END DO
!        DO i=1,dim
!        DO j=1,i-1
!           LES(i,j,1:n) = LES(j,i,1:n)
!        END DO
!        END DO
!     END IF
!#endif

     c = dim + 1

     ForceVector = 0.0d0
     MassMatrix  = 0.0d0
     StiffMatrix = 0.0d0
!------------------------------------------------------------------------------
!    Integration stuff
!------------------------------------------------------------------------------
     NBasis    = n
     Bubbles   = .FALSE.
     PBubbles  = .FALSE.
     Stabilize = StabilizeFlag
     IF ( .NOT.Stabilize .OR. Compressible1 .OR. Compressible2 ) THEN
       PBubbles = Element % BDOFs > 0
       IF ( PBubbles ) THEN
          NBasis = n + Element % BDOFs
       ELSE
          NBasis    = 2 * n
          Bubbles   = .TRUE.
       END IF
       Stabilize = .FALSE.
     END IF

     IF ( Bubbles ) THEN
       IntegStuff = GaussPoints( Element, Element % Type % GaussPoints2 )
     ELSE IF ( PBubbles ) THEN
       IntegStuff = GaussPoints( element, 2*NBasis )
     ELSE
       IntegStuff = GaussPoints( Element )
     END IF
     U_Integ => IntegStuff % u
     V_Integ => IntegStuff % v
     W_Integ => IntegStuff % w
     S_Integ => IntegStuff % s
     N_Integ =  IntegStuff % n
!------------------------------------------------------------------------------
!    Stabilization parameters: hK, mK (take a look at Franca et.al.)
!------------------------------------------------------------------------------
    
     IF ( Stabilize ) THEN
       hK = element % hK
       mK = element % StabilizationMK
     END IF
!------------------------------------------------------------------------------
!   Now we start integrating
!------------------------------------------------------------------------------
    DO t=1,N_Integ

      u = U_Integ(t)
      v = V_Integ(t)
      w = W_Integ(t)
!------------------------------------------------------------------------------
!     Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
      stat = ElementInfo( Element, Nodes, u, v, w, SqrtElementMetric, &
              Basis, dBasisdx, ddBasisddx, Stabilize, Bubbles )

      s = SqrtElementMetric * S_Integ(t)
!------------------------------------------------------------------------------
!     Density at the integration point
!------------------------------------------------------------------------------
      Density  = SUM( NodalDensity(1:n)*Basis(1:n) )
      IF ( Compressible1 ) THEN
        DO i=1,dim
          dTemperaturedx(i)  = SUM( NodalTemperature(1:n)  * dBasisdx(1:n,i) )
        END DO
        Pressure    = SUM( NodalPressure(1:n) * Basis(1:n) )
        Temperature = SUM( NodalTemperature(1:n) * Basis(1:n) )
      ELSE IF ( Compressible2 ) THEN
        DO i=1,dim
          dDensitydx(i)  = SUM( NodalDensity(1:n) * dBasisdx(1:n,i) )
        END DO
      ELSE IF ( PseudoCompressible ) THEN
        Pressure = SUM( NodalPressure(1:n) * Basis(1:n) )        
        Compress = Density * SUM(NodalCompressibility(1:n)*Basis(1:n))      
      END IF

!------------------------------------------------------------------------------
!     Velocity from previous iteration (relative to mesh velocity)
!     at the integration point
!------------------------------------------------------------------------------
      Velo = 0.0d0
      Velo(1) = SUM( (Ux(1:n)-MUx(1:n))*Basis(1:n) )
      Velo(2) = SUM( (Uy(1:n)-MUy(1:n))*Basis(1:n) )
      IF ( DIM > 2 ) Velo(3) = SUM( (Uz(1:n)-MUz(1:n))*Basis(1:n) )

      dVelodx = 0.0D0
      DO i=1,3
        dVelodx(1,i) = SUM( Ux(1:n) * dBasisdx(1:n,i) )
        dVelodx(2,i) = SUM( Uy(1:n) * dBasisdx(1:n,i) )
        IF ( DIM > 2 ) dVelodx(3,i) = SUM( Uz(1:n) * dBasisdx(1:n,i) )
      END DO
!------------------------------------------------------------------------------
!     Force at integration point
!------------------------------------------------------------------------------
      Force = 0.0d0
      DO i=1,c
        Force(i) = SUM( LoadVector(i,1:n) * Basis(1:n) )
      END DO

      LrF = LorentzForce( Element,Nodes,u,v,w )
      Force(1:DIM) = Force(1:DIM) + Lrf(1:DIM) / Density

!------------------------------------------------------------------------------
!     Additional forces due to gradient forces (electrokinetic flow) and
!     viscous drag in porous media.
!------------------------------------------------------------------------------

      IF(PotentialForce) THEN
        DO i=1,DIM
          Force(i) = Force(i) - SUM( PotentialCoefficient(1:n) * Basis(1:n) ) * &
              SUM(  PotentialField(1:n) * dBasisdx(1:n,i) )
        END DO
      END IF

      IF(Porous) THEN
        DO i=1,DIM
          Drag(i) = SUM( NodalDrag(i,1:n) * Basis(1:n) )
        END DO
      END IF

!------------------------------------------------------------------------------
!     Effective viscosity & derivatives at integration point
!------------------------------------------------------------------------------
      Viscosity = SUM( NodalViscosity(1:n) * Basis(1:n) )
      Viscosity = EffectiveViscosity( Viscosity, Density, Ux, Uy, Uz, &
                 Element, Nodes, n, n, u, v, w )


      IF ( Stabilize ) THEN
        DO i=1,3
          dViscositydx(i) = SUM( NodalViscosity(1:n)*dBasisdx(1:n,i) )
        END DO
!------------------------------------------------------------------------------
!      Stabilization parameters Tau & Delta
!------------------------------------------------------------------------------
       IF ( Convect ) THEN
          VNorm = MAX( SQRT( SUM(Velo(1:DIM)**2) ), 1.0d-12 )
          Re = MIN( 1.0d0, Density * mK * hK * VNorm / (4 * Viscosity) )

          Tau = hK * Re / (2 * Density * VNorm)
          Delta = Lambda * Re * hK * VNorm
       ELSE
          Delta = 2 * Viscosity / mK
          Tau   = mK * hK**2  / ( 4 * Viscosity )
       END IF

!------------------------------------------------------------------------------
!      SU will contain residual of ns-equations (except for the time derivative
!      and force terms). SW will contain the weight function values.
!------------------------------------------------------------------------------
       SU(1:n,:,:) = 0.0D0
       SW(1:n,:,:) = 0.0D0

       DO p=1,N
         DO i=1,DIM
           SU(p,i,c) = SU(p,i,c) + dBasisdx(p,i)

           IF(Porous) THEN
             SU(p,i,i) = SU(p,i,i) + Viscosity * Drag(i) * Basis(p)
           END IF

           IF ( Convect ) THEN
             DO j=1,DIM
               SU(p,i,i) = SU(p,i,i) + Density * dBasisdx(p,j) * Velo(j)

               SU(p,i,i) = SU(p,i,i) - Viscosity * ddBasisddx(p,j,j)

               SU(p,i,i) = SU(p,i,i) - dViscositydx(j) * dBasisdx(p,j)

               SU(p,i,j) = SU(p,i,j) - Viscosity * ddBasisddx(p,j,i)

               SU(p,i,j) = SU(p,i,j) - dViscositydx(j) * dBasisdx(p,i)
             END DO
           END IF

           IF ( Convect .AND. NewtonLinearization ) THEN
             DO j=1,DIM
               SU(p,i,j) = SU(p,i,j) + Density * dVelodx(i,j) * Basis(p)
             END DO
           END IF
!
!------------------------------------------------------------------------------

           SW(p,i,c) = SW(p,i,c) + Density * dBasisdx(p,i)

           IF ( Convect )  THEN
             DO j=1,DIM
               SW(p,i,i) = SW(p,i,i) + Density * dBasisdx(p,j) * Velo(j)

               SW(p,i,i) = SW(p,i,i) - Viscosity * ddBasisddx(p,j,j)
 
               SW(p,i,j) = SW(p,i,j) - dViscositydx(j) * dBasisdx(p,i)

               SW(p,i,j) = SW(p,i,j) - Viscosity * ddBasisddx(p,i,j)
 
               SW(p,i,i) = SW(p,i,i) - dViscositydx(j) * dBasisdx(p,j)
             END DO
           END IF
         END DO

       END DO
     END IF

!------------------------------------------------------------------------------
!    Loop over basis functions (of both unknowns and weights)
!------------------------------------------------------------------------------
     DO p=1,NBasis
     DO q=1,NBasis
!------------------------------------------------------------------------------
!      First plain Navier-Stokes
!------------------------------------------------------------------------------

       i = c*(p-1)
       j = c*(q-1)
       M => MassMatrix ( i+1:i+c,j+1:j+c )
       A => StiffMatrix( i+1:i+c,j+1:j+c )

!------------------------------------------------------------------------------
!      Mass matrix:
!------------------------------------------------------------------------------
! Momentum equations
       DO i=1,DIM
         M(i,i) = M(i,i) + s * Density * Basis(q) * Basis(p)
       END DO

! Continuity equation (in terms of pressure)
       IF ( Compressible1 ) THEN
         M(c,c) = M(c,c) + s * ( Density / Pressure ) * Basis(q) * Basis(p)
       END IF
!
!------------------------------------------------------------------------------
!      Stiffness matrix:
!------------------------------
! Possible Porous media effects
!------------------------------------------------------------------------------

        IF(Porous) THEN
          DO i=1,DIM
            A(i,i) = A(i,i) + s * Viscosity * Drag(i) * Basis(q) * Basis(p)
          END DO
        END IF

!------------------------------------------------------------------------------
!      Diffusive terms
!      Convection terms, Picard linearization
!------------------------------------------------------------------------------
       DO i=1,DIM
         DO j = 1,DIM
           A(i,i) = A(i,i) + s * Viscosity * dBasisdx(q,j) * dBasisdx(p,j)
           IF ( divDiscretization ) THEN
              A(i,j) = A(i,j) + s * Viscosity * dBasisdx(q,j) * dBasisdx(p,i)
           ELSE
              A(i,j) = A(i,j) + s * Viscosity * dBasisdx(q,i) * dBasisdx(p,j)
           END IF
           IF ( Convect ) THEN
              A(i,i) = A(i,i) + s * Density * dBasisdx(q,j) * Velo(j) * Basis(p)
           END IF
!------------------------------------------------------------------------------
!  For compressible flow add grad((2/3) \mu div(u))
!------------------------------------------------------------------------------
           IF ( Compressible1 .OR. Compressible2 ) THEN
             A(i,j) = A(i,j) - s * ( 2.0d0 / 3.0d0 ) * Viscosity * &
                        dBasisdx(q,j) * dBasisdx(p,i)
           END IF
!------------------------------------------------------------------------------

         END DO

 
         ! Pressure terms:
         ! --------------- 
         IF ( gradPDiscretization ) THEN
            A(i,c) = A(i,c) + s * dBasisdx(q,i) * Basis(p)
         ELSE
            A(i,c) = A(i,c) - s * Basis(q) * dBasisdx(p,i)
         END IF


         ! Continuity equation:
         !---------------------
         IF ( gradPDiscretization ) THEN
            A(c,i) = A(c,i) - s * Density * Basis(q) * dBasisdx(p,i)
         ELSE
            A(c,i) = A(c,i) + s * Density * dBasisdx(q,i) * Basis(p)
         END IF

         IF ( Compressible1 ) THEN
            A(c,c) = A(c,c) + s * ( Density / Pressure ) * &
                  Velo(i) * dBasisdx(q,i) * Basis(p)

            A(c,i) = A(c,i) - s * ( Density / Temperature ) * &
                dTemperaturedx(i) * Basis(q) * Basis(p)
         ELSE IF ( Compressible2 ) THEN
            A(c,i) = A(c,i) + s * dDensitydx(i) * Basis(q) * Basis(p)
         END IF
       END DO
!------------------------------------------------------------------------------
!      Artificial Compressibility, affects only the continuity equation
!------------------------------------------------------------------------------  
       IF (PseudoCompressible) THEN
          A(c,c) = A(c,c) + s * Compress * Basis(q) * Basis(p)
       END IF

!------------------------------------------------------------------------------
!      Convection, Newton linearization
!------------------------------------------------------------------------------
       IF ( Convect .AND. NewtonLinearization ) THEN
         DO i=1,DIM
           DO j=1,DIM
             A(i,j) = A(i,j) + s * Density * dVelodx(i,j) * Basis(q) * Basis(p)
           END DO
         END DO
       END IF

!------------------------------------------------------------------------------
!      Add stabilization...
!------------------------------------------------------------------------------
       IF ( Stabilize ) THEN 
          DO i=1,DIM
             DO j=1,c
                M(j,i) = M(j,i) + s * Tau * Density * Basis(q) * SW(p,i,j)
                DO k=1,c
                   A(j,k) = A(j,k) + s * Tau * SU(q,i,k) * SW(p,i,j)
                END DO
             END DO

             DO j=1,DIM
                A(j,i) = A(j,i) + &
                       s * Delta * Density * dBasisdx(q,i) * dBasisdx(p,j)
             END DO
          END DO
       END IF
     END DO
     END DO

!------------------------------------------------------------------------------
!    The righthand side...
!------------------------------------------------------------------------------
     IF ( Convect .AND. NewtonLinearization ) THEN
       DO i=1,dim
         DO j=1,dim
           Force(i) = Force(i) + dVelodx(i,j) * Velo(j)
         END DO
       END DO
     END IF

!#ifdef LES
!#define LSDelta (SQRT(2.0d0)*Element % hK)
!#define LSGamma 6
!     LSx=0
!     IF ( ASSOCIATED( LESVar ) ) THEN
!       DO i=1,dim
!       DO j=1,dim
!          LSx(i,j) = LSx(i,j) + SUM( Basis(1:n) * LES(i,j,1:n) )
!       END DO
!       END DO
!     ELSE
!       DO i=1,dim
!       DO j=1,dim
!          DO k=1,dim
!             LSx(i,j) = LSx(i,j) + dVelodx(i,k) * dVelodx(j,k)
!          END DO
!       END DO
!       END DO
!     END IF
!#endif


     DO p=1,NBasis
       Load => ForceVector( c*(p-1)+1 : c*(p-1)+c )

       DO i=1,c
         Load(i) = Load(i) + s * Density * Force(i) * Basis(p)
       END DO

!#ifdef LES
!       DO i=1,dim
!         DO j=1,dim
!            Load(i) = Load(i)+s*Density*LSDelta**2/(2*LSGamma)*LSx(i,j)*dBasisdx(p,j)
!         END DO
!       END DO
!#endif

       IF ( PseudoCompressible ) THEN
          Load(c) = Load(c) + s * Pressure * Basis(p) * Compress
       END IF

       IF ( Stabilize ) THEN
         DO i=1,DIM
           DO j=1,c
             Load(j) = Load(j) + s * Tau * Density * Force(i) * SW(p,i,j)
           END DO
         END DO
       END IF
     END DO
   END DO 
!------------------------------------------------------------------------------
 END SUBROUTINE NavierStokesCompose
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
 SUBROUTINE NavierStokesBoundary( BoundaryMatrix,BoundaryVector,LoadVector,   &
    NodalAlpha, NodalBeta, NodalExtPressure, NodalSlipCoeff, NormalTangential, Element, n, Nodes )
             
DLLEXPORT NavierStokesBoundary
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Return element local matrices and RSH vector for Navier-Stokes-equations
!  boundary conditions.
!
!  ARGUMENTS:
!
!  REAL(KIND=dp) :: BoundaryMatrix(:,:)
!     OUTPUT: time derivative coefficient matrix
!
!  REAL(KIND=dp) :: BoundaryVector(:)
!     OUTPUT: RHS vector
!
!  REAL(KIND=dp) :: LoadVector(:,:)
!     INPUT: Nodal values force in coordinate directions
!
!  REAL(KIND=dp) :: NodalAlpha(:,:)
!     INPUT: Nodal values of force in normal direction
!
!  REAL(KIND=dp) :: NodalBeta(:,:)
!     INPUT: Nodal values of something which will be taken derivative in
!            tangential direction and added to force...
!
!
!  TYPE(Element_t) :: Element
!       INPUT: Structure describing the element (dimension,nof nodes,
!               interpolation degree, etc...)
!
!  INTEGER :: n
!       INPUT: Number of boundary element nodes
!
!  TYPE(Nodes_t) :: Nodes
!       INPUT: Element node coordinates
!
!******************************************************************************
!------------------------------------------------------------------------------
   USE ElementUtils

   IMPLICIT NONE

   REAL(KIND=dp) :: BoundaryMatrix(:,:),BoundaryVector(:),LoadVector(:,:), &
     NodalAlpha(:),NodalBeta(:), NodalSlipCoeff(:,:), NodalExtPressure(:)

   INTEGER :: n,pn

   TYPE(Element_t),POINTER  :: Element, Parent
   TYPE(Nodes_t)    :: Nodes, ParentNodes

   LOGICAL :: NormalTangential

!------------------------------------------------------------------------------
!  Local variables
!------------------------------------------------------------------------------
   REAL(KIND=dp) :: Basis(n),dBasisdx(n,3),ddBasisddx(n,3,3)
   REAL(KIND=dp) :: SqrtElementMetric,FlowStress(3,3),SlipCoeff
#if 0
   REAL(KIND=dp) :: PBasis(pn),PdBasisdx(pn,3)
#endif

   REAL(KIND=dp) :: u,v,w,ParentU,ParentV,ParentW,s,x(n),y(n),z(n)
   REAL(KIND=dp), POINTER :: U_Integ(:),V_Integ(:),W_Integ(:),S_Integ(:)
   REAL(KIND=dp) :: Force(3),Normal(3),Tangent(3),Tangent2(3),Vect(3), Alpha, &
                 Viscosity,dVelodx(3,3),Velo(3)

   REAL(KIND=dp) :: xx, yy, ydot, ydotdot, MassFlux

   INTEGER :: i,j,k,k1,k2,t,q,p,c,DIM,N_Integ

   LOGICAL :: stat

   TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff

!------------------------------------------------------------------------------

   DIM = CoordinateSystemDimension()
   c = DIM + 1
!
!------------------------------------------------------------------------------
!  Integration stuff
!------------------------------------------------------------------------------
   IntegStuff = GaussPoints( element )
   U_Integ => IntegStuff % u
   V_Integ => IntegStuff % v
   W_Integ => IntegStuff % w
   S_Integ => IntegStuff % s
   N_Integ =  IntegStuff % n

!------------------------------------------------------------------------------
!  Now we start integrating
!------------------------------------------------------------------------------
   DO t=1,N_Integ

     u = U_Integ(t)
     v = V_Integ(t)
     w = W_Integ(t)
!------------------------------------------------------------------------------
!    Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
     stat = ElementInfo( Element,Nodes,u,v,w,SqrtElementMetric, &
                 Basis, dBasisdx, ddBasisddx, .FALSE. )

     s = SqrtElementMetric * S_Integ(t)
!------------------------------------------------------------------------------
!    Add to load: tangetial derivative of something
!------------------------------------------------------------------------------
     DO i=1,DIM
       Force(i) = SUM( NodalBeta(1:n)*dBasisdx(1:n,i) )
     END DO
!------------------------------------------------------------------------------
!    Add to load: given force in normal direction
!------------------------------------------------------------------------------
     Alpha = SUM( NodalExtPressure(1:n) * Basis )
!------------------------------------------------------------------------------
!    Add to load: given force in coordinate directions
!------------------------------------------------------------------------------
     DO i=1,DIM
       Force(i) = Force(i) + SUM( LoadVector(i,1:n)*Basis )
     END DO

     Normal = NormalVector( Element, Nodes, u,v,.TRUE. )
     DO i=1,DIM
        Force(i) = Force(i) + Alpha * Normal(i)
     END DO

     Alpha = SUM( NodalAlpha(1:n) * Basis )
     MassFlux = SUM( Loadvector(4,1:n) * Basis(1:n) )

#if 0
     IF ( ASSOCIATED(Parent) ) THEN
       Normal = NormalVector( Element, Nodes, u,v,.TRUE. )

       DO i = 1,n
         DO j = 1,pn
           IF ( Element % NodeIndexes(i) == Parent % NodeIndexes(j) ) THEN
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

       stat = ElementInfo( Parent, ParentNodes, ParentU, ParentV, ParentW, &
           SqrtElementMetric, PBasis, PdBasisdx, ddBasisddx, .FALSE. )

       Viscosity = SUM( NodalViscosity(1:pn) * PBasis )
       Viscosity = EffectiveViscosity( Viscosity,  Density, Ux, Uy, Uz, &
            Parent,ParentNodes,pn,pn,ParentU,ParentV,ParentW )
 
       dVelodx = 0.0d0
       DO i=1,3
         dVelodx(1,i) = SUM( Ux(1:pn) * PdBasisdx(1:pn,i) )
         dVelodx(2,i) = SUM( Uy(1:pn) * PdBasisdx(1:pn,i) )
         IF ( DIM > 2 ) &
           dVelodx(3,i) = SUM( Uz(1:pn) * PdBasisdx(1:pn,i) )
       END DO

       FlowStress = 0.0d0
       DO i=1,DIM
         DO j=1,DIM
           FlowStress(i,j) = FlowStress(i,j) + &
               Viscosity * ( dVelodx(i,j) + dVelodx(j,i) )
 
           FlowStress(i,i) = FlowStress(i,i) - (2.0d0/3.0d0) * &
                      Viscosity * dVelodx(j,j)
         END DO
         FlowStress(i,i) = FlowStress(i,i) - SUM( Pressure(1:pn) * PBasis )
       END DO

       DO q=1,N
         DO i=1,DIM
           k = (q-1)*c + i
           DO j=1,DIM
             BoundaryVector(k) = BoundaryVector(k) - s * Basis(q) * &
                          FlowStress(i,j) * Normal(j)
           END DO
         END DO
       END DO
     END IF
#endif


     SELECT CASE( Element % TYPE % DIMENSION )
     CASE(1)
        Tangent(1) =  Normal(2)
        Tangent(2) = -Normal(1)
        Tangent(3) =  0.0d0
     CASE(2)
        CALL TangentDirections( Normal, Tangent, Tangent2 ) 
     END SELECT

     IF ( ANY( NodalSlipCoeff(:,:) /= 0.0d0 ) ) THEN
       DO p=1,n
         DO q=1,n
           DO i=1,DIM
             SlipCoeff = SUM( NodalSlipCoeff(i,1:n) * Basis(1:n) )

             IF ( NormalTangential ) THEN
                SELECT CASE(i)
                   CASE(1)
                     Vect = Normal
                   CASE(2)
                     Vect = Tangent
                   CASE(3)
                     Vect = Tangent2
                END SELECT

                DO j=1,dim
                   DO k=1,dim
                      BoundaryMatrix( (p-1)*c+j,(q-1)*c+k ) = &
                         BoundaryMatrix( (p-1)*c+j,(q-1)*c+k ) + &
                          s * SlipCoeff * Basis(q) * Basis(p) * Vect(j) * Vect(k)
                   END DO
                END DO
             ELSE
                 BoundaryMatrix( (p-1)*c+i,(q-1)*c+i ) = &
                     BoundaryMatrix( (p-1)*c+i,(q-1)*c+i ) + &
                          s * SlipCoeff * Basis(q) * Basis(p)
             END IF
           END DO
         END DO
       END DO
     END IF

     DO q=1,N
       DO i=1,DIM
         k = (q-1)*c + i
         IF ( NormalTangential ) THEN
            SELECT CASE(i)
               CASE(1)
                 Vect = Normal
               CASE(2)
                 Vect = Tangent
               CASE(3)
                 Vect = Tangent2
            END SELECT

            DO j=1,dim
               k = (q-1)*c + j
               BoundaryVector(k) = BoundaryVector(k) + &
                 s * Basis(q) * Force(i) * Vect(j)
            END DO
         ELSE
            BoundaryVector(k) = BoundaryVector(k) + s * Basis(q) * Force(i)
         END IF
         BoundaryVector(k) = BoundaryVector(k) - s * Alpha * dBasisdx(q,i)
       END DO
       BoundaryVector(q*c) = BoundaryVector(q*c) + s * &
                          SUM( LoadVector(4,1:n) * Basis(1:n) ) * Basis(q)
     END DO

   END DO
!------------------------------------------------------------------------------
 END SUBROUTINE NavierStokesBoundary
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
 SUBROUTINE NavierStokesWallLaw( BoundaryMatrix,BoundaryVector,LayerThickness,&
    SurfaceRoughness,NodalViscosity,NodalDensity,Ux,Uy,Uz,Element,n,Nodes )
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Return element local matrices and RSH vector for Navier-Stokes-equations
!  boundary conditions.
!
!  ARGUMENTS:
!
!  REAL(KIND=dp) :: BoundaryMatrix(:,:)
!     OUTPUT: time derivative coefficient matrix
!
!  REAL(KIND=dp) :: BoundaryVector(:)
!     OUTPUT: RHS vector
!
!  REAL(KIND=dp) :: LayerThickness
!     INPUT: Boundary layer thickness
!
!  REAL(KIND=dp) :: SurfaceRoughness
!     INPUT: Measure of surface roughness (f.ex. 9)
!
!  REAL(KIND=dp) :: NodalViscosity(:)
!     INPUT: Nodal values of viscosity
!
!  REAL(KIND=dp) :: NodalDensity(:,:)
!     INPUT: Nodal values of density
!
!  REAL(KIND=dp) :: Ux(:),Uy(:),Uz(:)
!     INPUT: Nodal values of velocity from previous iteration
!
!  TYPE(Element_t) :: Element
!       INPUT: Structure describing the element (dimension,nof nodes,
!               interpolation degree, etc...)
!
!  INTEGER :: n
!       INPUT: Number of boundary element nodes
!
!  TYPE(Nodes_t) :: Nodes
!       INPUT: Element node coordinates
!
!******************************************************************************
!------------------------------------------------------------------------------

   IMPLICIT NONE

   REAL(KIND=dp) :: BoundaryMatrix(:,:),BoundaryVector(:), &
     NodalViscosity(:),NodalDensity(:),Ux(:),Uy(:),Uz(:)

   REAL(KIND=dp) :: LayerThickness(:),SurfaceRoughness(:)

   INTEGER :: n

   TYPE(Element_t),POINTER  :: Element
   TYPE(Nodes_t)    :: Nodes

!------------------------------------------------------------------------------
!  Local variables
!------------------------------------------------------------------------------
   REAL(KIND=dp) :: Basis(n),dBasisdx(n,3),ddBasisddx(n,3,3)
   REAL(KIND=dp) :: SqrtElementMetric

   REAL(KIND=dp) :: u,v,w,s,r,Density,Viscosity,Dist,Roughness
   REAL(KIND=dp) :: Velo(3),Normal(3),Tangent(3)
   REAL(KIND=dp) :: TangentialVelocity,FrictionVelocity,DFX,DKERR
   REAL(KIND=dp), POINTER :: U_Integ(:),V_Integ(:),W_Integ(:),S_Integ(:)

   INTEGER :: i,j,k1,k2,t,q,p,c,DIM,N_Integ

   LOGICAL :: stat

   TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff

!------------------------------------------------------------------------------

   DIM = CoordinateSystemDimension()
   c = DIM + 1

!------------------------------------------------------------------------------
!  Integration stuff
!------------------------------------------------------------------------------
   IntegStuff = GaussPoints( element )
   U_Integ => IntegStuff % u
   V_Integ => IntegStuff % v
   W_Integ => IntegStuff % w
   S_Integ => IntegStuff % s
   N_Integ =  IntegStuff % n

!------------------------------------------------------------------------------
!  Now we start integrating
!------------------------------------------------------------------------------
   DO t=1,N_Integ

     u = U_Integ(t)
     v = V_Integ(t)
     w = W_Integ(t)
!------------------------------------------------------------------------------
!    Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
     stat = ElementInfo( Element,Nodes,u,v,w,SqrtElementMetric, &
                 Basis,dBasisdx,ddBasisddx,.FALSE. )

     s = SqrtElementMetric * S_Integ(t)
!------------------------------------------------------------------------------
!    Density and viscosity at integration point
!------------------------------------------------------------------------------
     Density   = SUM( NodalDensity(1:n)*Basis )
     Viscosity = SUM( NodalViscosity(1:n)*Basis )
!------------------------------------------------------------------------------
!    Velocity from previous iteration at the integration point
!------------------------------------------------------------------------------
     Velo = 0.0d0
     Velo(1) = SUM( Ux(1:n)*Basis )
     Velo(2) = SUM( Uy(1:n)*Basis )
     IF ( DIM > 2 ) Velo(3) = SUM( Uz(1:n)*Basis )
!------------------------------------------------------------------------------
!    Normal & tangent directions
!------------------------------------------------------------------------------
     Normal = NormalVector( Element,Nodes,u,v,.FALSE. )
 
     IF ( DIM <= 2 ) THEN

       Tangent(1) = -Normal(2)
       Tangent(2) =  Normal(1)
       Tangent(3) =  0.0d0

     ELSE
!------------------------------------------------------------------------------
!       In 3D take tangent direction, that is perpendicular to normal (of
!       course) and the most like the velocity vector.
!------------------------------------------------------------------------------
        Tangent = Velo
        r  = SUM( Tangent(1:DIM) * Normal(1:DIM) )

        IF ( ABS(Normal(1)) > ABS(Normal(2)) .AND. &
             ABS(Normal(1)) > ABS(Normal(3)) ) THEN
          Tangent(1) = Tangent(1) - r / Normal(1)
        ELSE IF ( ABS(Normal(2)) > ABS(Normal(3)) ) THEN
          Tangent(2) = Tangent(2) - r / Normal(2)
        ELSE
          Tangent(3) = Tangent(3) - r / Normal(3)
        END IF
     END IF

     TangentialVelocity = SUM( Velo(1:DIM) * Tangent(1:DIM) )

     IF ( ABS(TangentialVelocity) < AEPS ) CYCLE

     IF ( TangentialVelocity < 0 ) THEN
       Tangent = -Tangent
       TangentialVelocity = -TangentialVelocity
     END IF

     Dist = SUM( LayerThickness(1:n) * Basis )
     Roughness = SUM( SurfaceRoughness(1:n) * Basis )

!------------------------------------------------------------------------------
!    Solve friction velocity and its derivative with respect to
!    the tangential velocity:
!------------------------------------------------------------------------------
     CALL Solve_UFric( Density,Viscosity,Dist,Roughness, &
          TangentialVelocity,FrictionVelocity,DFX )

     DKERR = 2.0d0 * Density * FrictionVelocity / DFX
!------------------------------------------------------------------------------
     DO p=1,N
       DO q=1,N
         DO i=1,DIM
           DO j=1,DIM
             k1 = (p-1)*c + i
             k2 = (q-1)*c + j
             BoundaryMatrix(k1,k2) = BoundaryMatrix(k1,k2) + &
               s * DKERR * Tangent(i) * Tangent(j) * Basis(q) * Basis(p)
           END DO
         END DO
       END DO
     END DO
!------------------------------------------------------------------------------
     DO q=1,N
       DO i=1,DIM
         k1 = (q-1)*c + i
         BoundaryVector(k1) = BoundaryVector(k1) + &
           s * ( DKERR * TangentialVelocity - &
             Density * FrictionVelocity**2 ) * Tangent(i) * Basis(q)
       END DO
     END DO
   END DO

!------------------------------------------------------------------------------

#if 0
   DO i=1,n
     IF ( ABS(Normal(1)) > ABS(Normal(2)) .AND. ABS(Normal(1)) > ABS(Normal(3)) ) THEN
       DO j=1,n
          BoundaryMatrix((i-1)*c+1,(i-1)*c+j) = Normal(j) * 1.0d12
       END DO
     ELSE IF ( ABS(Normal(2)) > ABS(Normal(3)) ) THEN
       DO j=1,n
         BoundaryMatrix((i-1)*c+2,(i-1)*c+j) = Normal(j) * 1.0d12
       END DO
     ELSE
       DO j=1,n
         BoundaryMatrix((i-1)*c+3,(i-1)*c+j) = Normal(j) * 1.0d12
       END DO
     END IF
   END DO
#endif

!------------------------------------------------------------------------------
 END SUBROUTINE NavierStokesWallLaw
!------------------------------------------------------------------------------

END MODULE NavierStokes
