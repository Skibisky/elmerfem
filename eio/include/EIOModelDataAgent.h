/***********************************************************************
*
*       ELMER, A Computational Fluid Dynamics Program.
*
*       Copyright 1st April 1995 - , Center for Scientific Computing,
*                                    Finland.
*
*       All rights reserved. No part of this program may be used,
*       reproduced or transmitted in any form or by any means
*       without the written permission of CSC.
*
*                Address: Center for Scientific Computing
*                         Tietotie 6, P.O. BOX 405
*                         02101 Espoo, Finland
*                         Tel.     +358 0 457 2001
*                         Telefax: +358 0 457 2302
*                         EMail:   Jari.Jarvinen@csc.fi
************************************************************************/

/***********************************************************************
Program:    ELMER Data base interface (EIO)
Author(s):  Harri Hakula 10.03.98
************************************************************************/

#ifndef EIOMODELDATAAGENT_H
#define EIOMODELDATAAGENT_H

#include "EIOModelManager.h"

// Changed from 10 --> 3
// Martti Verho, 19.10.98
// Ref. also array definitions in
// EIOModelDataAgetn.cpp
//const int modelDataFiles = 10;
const int modelDataFiles = 3;

class EIOModelDataAgent
{
public:
  EIOModelDataAgent(EIOModelManager *mm);
  ~EIOModelDataAgent();

  int createModelData();
  int openModelData();
  int closeModelData();

  int writeDescription(int& bodies,
		       int& body_forces,
		       int& body_equations,
		       int& materials,
		       int& boundary_conditions,
		       int& initial_conditions,
		       int& mesh_parameters);
  int readDescription(int& bodies,
		      int& body_forces,
		      int& body_equations,
		      int& materials,
		      int& boundary_conditions,
		      int& initial_conditions,
		      int& mesh_parameters);
  int writeBodyRecord(int& tag, int& body_force_id,
			  int& equation_id, int& init_cond_id,
			  int& material_id, int& mesh_param_id);
  int readBodyRecord(int& tag, int& body_force_id,
			  int& equation_id, int& init_cond_id,
			  int& material_id, int& mesh_param_id);

  int writeConstants(double* gravity, double& boltz);
  int readConstants(double* gravity, double& boltz);

  int writeCoordinates(int& dim, int& coordsys, int *mapping,
				  int& symmetry,
				  double *start,
				  double *end1, double* end2);
  int readCoordinates(int& dim, int& coordsys, int *mapping,
				  int& symmetry,
				  double *start,
				  double *end1, double* end2);

  int writeMaterialHead(int& tag, int& fields);
  int writeMaterialField(int& name, int& type, int& len, int* fields, double* values);

  int readMaterialHead(int& tag, int& fields);
  int readMaterialField(int& name, int& type,  int& len, int* fields, double* values);
  
  int writeBoundaryConditionHead(int& tag, int& fields);
  int writeBoundaryConditionField(int& name, int& type,  int& len, int* fields, double* values);
  int readBoundaryConditionHead(int& tag, int& fields);
  int readBoundaryConditionField(int& name, int& type,  int& len, int* fields, double* values);
  
  int writeInitialConditionHead(int& tag, int& fields);
  int writeInitialConditionField(int& name, int& type,  int& len, int* fields, double* values);
  int readInitialConditionHead(int& tag, int& fields);
  int readInitialConditionField(int& name, int& type,  int& len, int* fields, double* values);
  
  int writeBodyEquationHead(int& tag, int& fields);
  int writeBodyEquationField(int& name, int& type,  int& len, int* fields, double* values);
  int readBodyEquationHead(int& tag, int& fields);
  int readBodyEquationField(int& name, int& type,  int& len, int* fields, double* values);
  
  int writeBodyForceHead(int& tag, int& fields);
  int writeBodyForceField(int& name, int& type,  int& len, int* fields, double* values);
  int readBodyForceHead(int& tag, int& fields);
  int readBodyForceField(int& name, int& type,  int& len, int* fields, double* values);
  
  int writeMeshParameterHead(int& tag, int& fields);
  int writeMeshParameterField(int& name, int& type,  int& len, int* fields, double* values);
  int readMeshParameterHead(int& tag, int& fields);
  int readMeshParameterField(int& name, int& type,  int& len, int* fields, double* values);
  
private:
  // We "use" ModelManager in every Agent.
  EIOModelManager *manager;

  // All streams
  fstream modelDataFileStream[modelDataFiles];
  // Sizes
};

#endif /* EIOMODELDATAAGENT_H */
