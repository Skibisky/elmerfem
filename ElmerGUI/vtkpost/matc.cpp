/*****************************************************************************
 *                                                                           *
 *  Elmer, A Finite Element Software for Multiphysical Problems              *
 *                                                                           *
 *  Copyright 1st April 1995 - , CSC - Scientific Computing Ltd., Finland    *
 *                                                                           *
 *  This program is free software; you can redistribute it and/or            *
 *  modify it under the terms of the GNU General Public License              *
 *  as published by the Free Software Foundation; either version 2           *
 *  of the License, or (at your option) any later version.                   *
 *                                                                           *
 *  This program is distributed in the hope that it will be useful,          *
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of           *
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            *
 *  GNU General Public License for more details.                             *
 *                                                                           *
 *  You should have received a copy of the GNU General Public License        *
 *  along with this program (in file fem/GPL-2); if not, write to the        *
 *  Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,         *
 *  Boston, MA 02110-1301, USA.                                              *
 *                                                                           *
 *****************************************************************************/

/*****************************************************************************
 *                                                                           *
 *  ElmerGUI surface                                                         *
 *                                                                           *
 *****************************************************************************
 *                                                                           *
 *  Authors: Mikko Lyly, Juha Ruokolainen and Peter R�back                   *
 *  Email:   Juha.Ruokolainen@csc.fi                                         *
 *  Web:     http://www.csc.fi/elmer                                         *
 *  Address: CSC - Scientific Computing Ltd.                                 *
 *           Keilaranta 14                                                   *
 *           02101 Espoo, Finland                                            *
 *                                                                           *
 *  Original Date: 15 Mar 2008                                               *
 *                                                                           *
 *****************************************************************************/

#include <QtGui>
#include <iostream>
#include "epmesh.h"
#include "matc.h"
#include "vtkpost.h"

#include <vtkFloatArray.h>
#include <vtkUnstructuredGrid.h>
#include <vtkCellDerivatives.h>
#include <vtkPointData.h>
#include <vtkCellDataToPointData.h>

using namespace std;

Matc::Matc(QWidget *parent)
  : QDialog(parent)
{
  ui.setupUi(this);

  connect(ui.mcOK, SIGNAL(clicked()), this, SLOT(okButtonClicked()));
  setWindowIcon(QIcon(":/icons/Mesh3D.png"));

  mtc_init( NULL, stdout, stderr );
  QString elmerGuiHome = getenv("ELMERGUI_HOME");
  QString mcIniLoad = "source(\"" + elmerGuiHome.replace("\\", "/") + "/edf/mc.ini\")";
  mtc_domath( mcIniLoad.toAscii().data() );

  com_init( (char *)"grad", FALSE, FALSE, com_grad, 1, 1,
            (char *)"r = grad(f): compute gradient of a scalar variable f.\n") ;

  com_init( (char *)"div", FALSE, FALSE, com_div, 1, 1,
            (char *)"r = div(f): compute divergence of a vector variable f.\n") ;

  com_init( (char *)"curl", FALSE, FALSE, com_curl, 1, 1,
            (char *)"r = curl(f): compute curl of a vector variable f.\n") ;

  in = NULL;
  out = NULL;
}

Matc::~Matc()
{
}


void Matc::okButtonClicked()
{
  close();
}

void Matc::setInput(double* ptr)
{
  in = ptr;
}

void Matc::setOutput(double* ptr)
{
  out = ptr;
}

void Matc::grad(VtkPost* vtkPost)
{
  vtkUnstructuredGrid* volumeGrid = vtkPost->GetVolumeGrid();
  vtkUnstructuredGrid* surfaceGrid = vtkPost->GetSurfaceGrid();
  
  vtkFloatArray *s = vtkFloatArray::New();
  s->SetNumberOfComponents(1);
  s->SetNumberOfTuples(vtkPost->NofNodes());
  for( int i=0;i<vtkPost->NofNodes(); i++ )
    s->SetValue(i,in[i] );
  
  vtkCellDerivatives *cd = vtkCellDerivatives::New();
  if ( volumeGrid->GetNumberOfCells()>0 ) {
    volumeGrid->GetPointData()->SetScalars(s);
    cd->SetInput(volumeGrid);
  } else {
    surfaceGrid->GetPointData()->SetScalars(s);
    cd->SetInput(surfaceGrid);
  }
  cd->SetVectorModeToComputeGradient();
  cd->Update();
  
  vtkCellDataToPointData *nd = vtkCellDataToPointData::New();
  nd->SetInput(cd->GetOutput());
  nd->Update();
  
  vtkDataArray *da = nd->GetOutput()->GetPointData()->GetVectors();
  int ncomp = da->GetNumberOfComponents();
  for( int i=0; i<vtkPost->NofNodes(); i++ )
    for( int j=0; j<ncomp; j++ )
      out[vtkPost->NofNodes()*j+i] = da->GetComponent(i,j);
  
  cd->Delete();
  nd->Delete();
  s->Delete(); 
}

void Matc::div(VtkPost* vtkPost)
{
  vtkUnstructuredGrid* volumeGrid = vtkPost->GetVolumeGrid();
  vtkUnstructuredGrid* surfaceGrid = vtkPost->GetSurfaceGrid();

  int n=volumeGrid->GetNumberOfCells();
  int ncomp = 3;
  
  vtkFloatArray *s = vtkFloatArray::New();
  s->SetNumberOfComponents(ncomp);
  s->SetNumberOfTuples(vtkPost->NofNodes());
  
  for( int j=0;j<ncomp; j++ )
    for( int i=0;i<vtkPost->NofNodes(); i++ )
      s->SetComponent(i,j,in[j*vtkPost->NofNodes()+i] );
  
  vtkCellDerivatives *cd = vtkCellDerivatives::New();
  if ( n>0 ) {
    volumeGrid->GetPointData()->SetVectors(s);
    cd->SetInput(volumeGrid);
  } else {
    surfaceGrid->GetPointData()->SetVectors(s);
    cd->SetInput(surfaceGrid);
  }
  cd->SetTensorModeToComputeGradient();
  cd->Update();
  
  vtkCellDataToPointData *nd = vtkCellDataToPointData::New();
  nd->SetInput(cd->GetOutput());
  nd->Update();
  
  vtkDataArray *da = nd->GetOutput()->GetPointData()->GetTensors();
  ncomp = da->GetNumberOfComponents();
  for( int i=0; i<vtkPost->NofNodes(); i++ )
    {
      out[i]  = da->GetComponent(i,0);
      out[i] += da->GetComponent(i,4);
      out[i] += da->GetComponent(i,8);
    }
  cd->Delete();
  nd->Delete();
  s->Delete(); 
}


void Matc::curl(VtkPost* vtkPost)
{
  vtkUnstructuredGrid* volumeGrid = vtkPost->GetVolumeGrid();
  vtkUnstructuredGrid* surfaceGrid = vtkPost->GetSurfaceGrid();

  int n=volumeGrid->GetNumberOfCells();
  int ncomp = 3;
  
  vtkFloatArray *s = vtkFloatArray::New();
  s->SetNumberOfComponents(ncomp);
  s->SetNumberOfTuples(vtkPost->NofNodes());
  
  for( int j=0;j<ncomp; j++ )
    for( int i=0;i<vtkPost->NofNodes(); i++ )
      s->SetComponent(i,j,in[j*vtkPost->NofNodes()+i] );
  
  vtkCellDerivatives *cd = vtkCellDerivatives::New();
  if ( n>0 ) {
    volumeGrid->GetPointData()->SetVectors(s);
    cd->SetInput(volumeGrid);
  } else {
    surfaceGrid->GetPointData()->SetVectors(s);
    cd->SetInput(surfaceGrid);
  }
  cd->SetTensorModeToComputeGradient();
  cd->Update();
  
  vtkCellDataToPointData *nd = vtkCellDataToPointData::New();
  nd->SetInput(cd->GetOutput());
  nd->Update();
  
  vtkDataArray *da = nd->GetOutput()->GetPointData()->GetTensors();
  for( int i=0; i<vtkPost->NofNodes(); i++ )
    {
      double gx_x = da->GetComponent(i,0);
      double gx_y = da->GetComponent(i,3);
      double gx_z = da->GetComponent(i,6);
      double gy_x = da->GetComponent(i,1);
      double gy_y = da->GetComponent(i,4);
      double gy_z = da->GetComponent(i,7);
      double gz_x = da->GetComponent(i,2);
      double gz_y = da->GetComponent(i,5);
      double gz_z = da->GetComponent(i,8);
      out[i] = gz_y-gy_z;
      out[vtkPost->NofNodes()+i] = gx_z-gz_x;
      out[2*vtkPost->NofNodes()+i] = gy_x-gx_y;
    }
  
  cd->Delete();
  nd->Delete();
  s->Delete(); 
}

void Matc::domatc(VtkPost* vtkPost)
{
  int scalarFields = vtkPost->GetScalarFields();
  int n=vtkPost->NofNodes();
  ScalarField* scalarField = vtkPost->GetScalarField();

  char *ptr;
  LIST *lst;
  VARIABLE *var;
  
  QString cmd=ui.mcEdit->text().trimmed();

  ui.mcEdit->clear();
  
  ptr=mtc_domath(cmd.toAscii().data());
  ui.mcHistory->append(cmd);
  if ( ptr ) ui.mcOutput->append(ptr);
  
  for( lst = listheaders[VARIABLES].next; lst; lst = NEXT(lst))
    {
      var = (VARIABLE *)lst;
      if ( !NAME(var) || (NCOL(var) % n)!=0 ) continue;
      
      int found = false;
      for( int i=0; i < scalarFields; i++ )
      {
        ScalarField *sf = &scalarField[i]; 
        if ( NROW(var)==1 && sf->name == NAME(var) )
        {
          found = true;
          if ( sf->value != MATR(var) ) {
            free(sf->value);
            sf->value  = MATR(var);
            sf->values = NCOL(var);
          }
          vtkPost->minMax(sf);
          break;
	} else if ( NROW(var)==3 ) {
          QString vectorname = "";
          int ns=sf->name.indexOf("_x"), ind=0;
          if (ns<=0) { ns=sf->name.indexOf("_y"); ind=1; }
          if (ns<=0) { ns=sf->name.indexOf("_z"); ind=2; }
          if (ns >0) vectorname=sf->name.mid(0,ns);
	   
          if ( vectorname==NAME(var) )
          {
            found = true;
            if ( sf->value != &M(var,ind,0) ) {
               free(sf->value);
               sf->values = NCOL(var);
               sf->value  = &M(var,ind,0);
             }
             vtkPost->minMax(sf);
          }
        }
      }
      
      if ( !found ) 
	{
          ScalarField *sf;
	  if ( NROW(var) == 1 ) {
            sf = vtkPost->addScalarField( NAME(var),NCOL(var),NULL ); vtkPost->minMax(sf);
	  } else if ( NROW(var) == 3 ) {
	    QString qs = NAME(var);
	    sf=vtkPost->addScalarField(qs+"_x",NCOL(var),&M(var,0,0)); vtkPost->minMax(sf);
	    sf=vtkPost->addScalarField(qs+"_y",NCOL(var),&M(var,1,0)); vtkPost->minMax(sf);
	    sf=vtkPost->addScalarField(qs+"_z",NCOL(var),&M(var,2,0)); vtkPost->minMax(sf);
	  }
	}
    }

  // we may have added fields, ask again...
  scalarFields = vtkPost->GetScalarFields();

  int count=0;
  for( int i=0; i<scalarFields; i++ )
    {
      ScalarField *sf = &scalarField[i]; 
      
      QString vectorname = "";
      int ns=sf->name.indexOf("_x");
      if ( ns<=0 ) ns=sf->name.indexOf("_y");
      if ( ns<=0 ) ns=sf->name.indexOf("_z");
      if ( ns >0 ) vectorname=sf->name.mid(0,ns);
      
      for( lst = listheaders[VARIABLES].next; lst; lst = NEXT(lst))
	{
	  var = (VARIABLE *)lst;
	  if ( !NAME(var) || (NCOL(var) % n)!=0 ) continue;
	  
	  if ( NROW(var)==1 && sf->name == NAME(var) )
	    {
	      if ( count != i ) scalarField[count]=*sf;
	      count++;
	      break;
	    } else if ( NROW(var)==3 && vectorname==NAME(var) ) {
	    if ( count != i ) scalarField[count]=*sf;
	    count++;
	  }
	}
    }
  if ( count<scalarFields ) vtkPost->SetScalarFields(count);
}

VARIABLE *Matc::com_grad(VARIABLE *in)
{
   VARIABLE *out; 
   int n=vtkp->NofNodes(),nsteps=NCOL(in)/n;

   out = var_temp_new(TYPE_DOUBLE,3,NCOL(in));
   if ( nsteps==1 ) {
     vtkp->grad(MATR(in), MATR(out) );
   } else {
     int nsize=n*sizeof(double);
     double *outf = (double *)malloc(3*nsize);
     for( int i=0; i<nsteps; i++ )
     {
       vtkp->grad( &M(in,0,i*n),outf );

       memcpy( &M(out,0,i*n), &outf[0], nsize );
       memcpy( &M(out,1,i*n), &outf[n], nsize );
       memcpy( &M(out,2,i*n), &outf[2*n], nsize );
     }
     free(outf);
   }
   return out;
}

VARIABLE *Matc::com_div(VARIABLE *in)
{
   VARIABLE *out; 
   int n=vtkp->NofNodes(),nsteps=NCOL(in)/n;

   out = var_temp_new(TYPE_DOUBLE,1,NCOL(in));
   if ( nsteps==1 ) {
     vtkp->div(MATR(in), MATR(out) );
   } else {
     int nsize=n*sizeof(double);
     double *inf = (double *)malloc(3*nsize);
     for( int i=0; i<nsteps; i++ )
     {
       memcpy( &inf[0], &M(in,0,i*n), nsize );
       memcpy( &inf[n], &M(in,1,i*n), nsize );
       memcpy( &inf[2*n], &M(in,2,i*n), nsize );

       vtkp->div(inf,&M(out,0,i*n));
     }
     free(inf);
   }
   return out;
}

VARIABLE *Matc::com_curl(VARIABLE *in)
{
   VARIABLE *out; 
   int n=vtkp->NofNodes(),nsteps=NCOL(in)/n;

   out = var_temp_new(TYPE_DOUBLE,3,NCOL(in));
   if ( nsteps==1 ) {
     vtkp->curl(MATR(in), MATR(out) );
   } else {
     int nsize=n*sizeof(double);
     double *inf  = (double *)malloc(3*nsize);
     double *outf = (double *)malloc(3*nsize);
     for( int i=0; i<nsteps; i++ )
     {
       memcpy( &inf[0], &M(in,0,i*n), nsize);
       memcpy( &inf[n], &M(in,1,i*n), nsize);
       memcpy( &inf[2*n], &M(in,2,i*n), nsize);

       vtkp->curl(inf,outf);

       memcpy( &M(out,0,i*n), &outf[0], nsize );
       memcpy( &M(out,1,i*n), &outf[n], nsize );
       memcpy( &M(out,2,i*n), &outf[2*n], nsize );
     }
     free(inf); free(outf);
   }
   return out;
}
