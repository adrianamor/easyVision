#include "lapack-aux.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define MACRO(B) do {B} while (0)
#define ERROR(CODE) MACRO(return CODE;)
#define REQUIRES(COND, CODE) MACRO(if(!(COND)) {ERROR(CODE);})

#define MIN(A,B) ((A)<(B)?(A):(B))
#define MAX(A,B) ((A)>(B)?(A):(B))
 
#ifdef DBG
#define DEBUGMSG(M) printf("LAPACK Wrapper "M": "); size_t t0 = time(NULL);
#define OK MACRO(printf("%ld s\n",time(0)-t0); return 0;);
#else
#define DEBUGMSG(M)
#define OK return 0;
#endif

#define CHECK(RES,CODE) MACRO(if(RES) return CODE;)

#define BAD_SIZE 1000
#define BAD_CODE 1001
#define MEM      1002
#define BAD_FILE 1003

//////////////////// real svd ////////////////////////////////////

void dgesdd_ (int*,
              int*,int*,double*,int*,
              double*,
              double*,int*,
              double*,int*,
              double*,int*,
              int*,
              int*);

int svd_l_Rdd(KDMAT(a),DMAT(u), DVEC(s),DMAT(v)) {
    int m = ar;
    int n = ac;
    int q = MIN(m,n);
    REQUIRES(ur==m && uc==m && sn==q && vr==n && vc==n,BAD_SIZE);
    DEBUGMSG("svd_l_Rdd");
    double *B = (double*)malloc(m*n*sizeof(double));
    CHECK(!B,MEM);
    memcpy(B,ap,m*n*sizeof(double));
    int* iwk = (int*) malloc(8*q*sizeof(int));
    CHECK(!iwk,MEM);
    int lwk = -1;
    int job = 'A';
    int res;
    // ask for optimal lwk
    double ans;
    //printf("ask dgesdd\n");
    dgesdd_ (&job,&m,&n,B,&m,sp,up,&m,vp,&n,&ans,&lwk,iwk,&res);
    lwk = 2*ceil(ans); // ????? otherwise 50x100 rejects lwk
    //printf("lwk = %d\n",lwk);
    double * workv = (double*)malloc(lwk*sizeof(double));
    CHECK(!workv,MEM);
    //printf("dgesdd\n");
    dgesdd_ (&job,&m,&n,B,&m,sp,up,&m,vp,&n,workv,&lwk,iwk,&res);
    CHECK(res,res);
    free(iwk);
    free(workv);
    free(B);
    OK
}

void dgesvd_ (int*,int*,              // jobu, jobvt
              int*,int*,double*,int*, // m, n, a, lda
              double*,                // s 
              double*,int*,           // u, ldu
              double*,int*,           // vt, ldvt
              double*,int*,           // work, lwork
              int*);                  // info

int svd_l_R(KDMAT(a),DMAT(u), DVEC(s),DMAT(v)) {
    int m = ar;
    int n = ac;
    int q = MIN(m,n);
    REQUIRES(ur==m && uc==m && sn==q && vr==n && vc==n,BAD_SIZE);
    DEBUGMSG("svd_l_R");
    double *B = (double*)malloc(m*n*sizeof(double));
    CHECK(!B,MEM);
    memcpy(B,ap,m*n*sizeof(double));
    int lwork = -1;
    int jobu  = 'A';
    int jobvt = 'A';
    int res;
    // ask for optimal lwork
    double ans;
    //printf("ask zgesvd\n");
    dgesvd_ (&jobu,&jobvt,
             &m,&n,B,&m,
             sp,
             up,&m,
             vp,&n,
             &ans, &lwork,
             &res);
    lwork = ceil(ans);
    //printf("ans = %d\n",lwork);
    double * work = (double*)malloc(lwork*sizeof(double));
    CHECK(!work,MEM);
    //printf("dgesdd\n");
    dgesvd_ (&jobu,&jobvt,
             &m,&n,B,&m,
             sp,
             up,&m,
             vp,&n,
             work, &lwork,
             &res);
    CHECK(res,res);
    free(work);
    free(B);
    OK
}



//////////////////// complex svd ////////////////////////////////////

void zgesvd_ (int*,int*,              // jobu, jobvt
              int*,int*,double*,int*, // m, n, a, lda
              double*,                // s 
              double*,int*,           // u, ldu
              double*,int*,           // vt, ldvt
              double*,int*,           // work, lwork
              double*,                // rwork
              int*);                  // info

int svd_l_C(KCMAT(a),CMAT(u), DVEC(s),CMAT(v)) {
    int m = ar;
    int n = ac;
    int q = MIN(m,n);
    REQUIRES(ur==m && uc==m && sn==q && vr==n && vc==n,BAD_SIZE);
    DEBUGMSG("svd_l_C");
    double *B = (double*)malloc(2*m*n*sizeof(double));
    CHECK(!B,MEM);
    memcpy(B,ap,m*n*2*sizeof(double));

    double *rwork = (double*) malloc(5*q*sizeof(double));
    CHECK(!rwork,MEM);
    int lwork = -1;
    int jobu  = 'A';
    int jobvt = 'A';
    int res;
    // ask for optimal lwork
    double ans;
    //printf("ask zgesvd\n");
    zgesvd_ (&jobu,&jobvt,
             &m,&n,B,&m,
             sp,
             up,&m,
             vp,&n,
             &ans, &lwork,
             rwork,
             &res);
    lwork = ceil(ans);
    //printf("ans = %d\n",lwork);
    double * work = (double*)malloc(lwork*2*sizeof(double));
    CHECK(!work,MEM);
    //printf("dgesdd\n");
    zgesvd_ (&jobu,&jobvt,
             &m,&n,B,&m,
             sp,
             up,&m,
             vp,&n,
             work, &lwork,
             rwork,
             &res);
    CHECK(res,res);
    free(work);
    free(rwork);
    free(B);
    OK
}