\c 22 100
\l funq.q
\l mlense.q

-1"to ensure the ratings matrix only contains movies with relevant movies,";
-1"we generate a list of unique movie ids that meet our threshold.";
show m:exec distinct asc movieId from mlense.rating where 100<(count;i) fby movieId

/ personal ratings

-1"we now build a dataset to hold our own ratings/preferences";
r:([movieId:m]rating:count[m]#0n) / initial ratings
r:r lj ([movieId:173 208 260 435 1197 2005 1968 2918i]rating:.5 .5 4 .5 4 4 4 5f)
r:r lj ([movieId:4006 53996 69526 87520 112370i]rating:5 4 4 5 5f)
show select from r lj mlense.movie where not null rating  / my ratings

/ projection to sort ratings and append movie title
rpt:lj[;mlense.movie] `score xdesc

/ http://files.grouplens.org/papers/FnT%20CF%20Recsys%20Survey.pdf

/ content based filtering

-1"content based filtering does not use ratings from other people.";
-1"it uses our own preferences mixed with each movie's genre";
Y:enlist value[r]`rating
-1"we build the X matrix based on each movie's genres";
show X:"f"$flip exec genre in/: genres from ([]movieId:m)#mlense.movie
-1"we then randomly initialize the THETA matrix";
theta:raze 0N!THETA:-1+(1+count X)?/:count[Y]#2f;
-1"since we don't use other user's preferences, this is quick optimization";
l1:0;l2:.2                     / L1 and L2 regularization coefficients
theta:first .fmincg.fmincg[20;.ml.rlincostgrad[l1;l2;X;Y];theta] / learn
THETA:(count[Y];0N)#theta
-1"view our deduced genre preferences";
show {(5#x),-5#x}desc genre!1_last THETA
-1"how closely do the computed scores match our preferences";
show rpt select from (update score:last .ml.predict[X;THETA] from r) where not null rating
-1"and finally, show the recommendations";
show rpt update score:last .ml.predict[X;THETA] from r

/ ratings data summary

/ http://webdam.inria.fr/Jorge/html/wdmch19.html
-1"we begin be reporting summary statistics about the ratings dataset";
-1"support";
-1"reporting the number of users, movies and ratings";
show exec nu:count distinct userId, nm:count distinct movieId, nr:count i from mlense.rating
-1"distribution:";
-1"we can see that only users with >20 ratings are included";
show select nu:count userId by nr from select nr:10 xbar count rating by userId from mlense.rating
-1"we can also see that a large majority of movies have less than 10 ratings";
show select nm:count movieId by nr from select nr:10 xbar count rating by movieId from mlense.rating
-1"quality:";
-1"we can see that there is a positive bias to the ratings";
show exec `min`med`avg`mode`max!(min;med;avg;.ml.mode;max)@\:rating from mlense.rating
/rating:select from rating where 19<(count;i) fby userId,9<(count;i) fby movieId
-1"the average rating per user (and movie) is distributed around 3.5";
t:select nm:count i by rating from select .5 xbar avg rating by movieId from mlense.rating
show t lj select nu:count i by rating from select .5 xbar avg rating by userId from mlense.rating
-1"movies with a small number of ratings can distort the rankings";
-1"the top rankings are dominated by movies with a single rating";
show select[10;>rating] avg rating, n:count i by movieId.title from mlense.rating
-1"while the most rated movies have averages centered around 4";
show select[10;>n] avg rating, n:count i by movieId.title from mlense.rating
-1"we will therefore demean the ratings before performing our analysis";
-1"";
-1"by using a syntax that is similar to pivoting,";
-1"we can generate the user/movie matrix";

show R:value exec (movieId!rating) m by userId from mlense.rating where ([]movieId) in key r
-1"then add our own ratings";
R,:value[r]`rating
-1"demean the data and store global/movie/user bias";
b:avg 2 raze/ R
Y:Y-ub:avg each Y:Y-\:mb:.ml.navg Y:R-b
y:r-'mb+b+last ub

/ user user collaborative filtering

-1"user-user collaborative filtering fills missing ratings";
-1"with averaged values from users who's ratings are most similar to ours";
-1"we have many choices to make:";
-1"[ ] should we use Pearson's correlation (cor) or Spearman's (.ml.scor)";
-1"[ ] should we use cosine similarity instead?";

-1"average top n users based on correlation";
show rpt b+mb+'last[ub]+update score:.ml.uucf[cor;.ml.tnavg 20;0^Y] rating from y
-1"weighted average top n users based on spearman correlation";
show rpt b+mb+'last[ub]+update score:.ml.uucf[.ml.scor;.ml.tnwavg 20;0^Y] rating from y
-1"weighted average top n users based on cosine similarity";
show rpt b+mb+'last[ub]+update score:.ml.uucf[.ml.cossim;.ml.tnwavg 20;0^Y] rating from y
-1"what if we would like recommend more niche movies.";
-1"ie: underweight movies with more ratings?";
-1"we can use the 'idf' (inverse document frequency) calculation ";
-1"from nlp (natural language processing)";
-1"weighted average top n users based on cosine similarity of idf-adjusted ratings";
/ weight by inverse user frequencies to underweight universally liked movies
show rpt b+mb+'last[ub]+update score:.ml.uucf['[.ml.cossim . .ml.idf[Y]*/:;enlist];.ml.tnwavg[20];0^Y] rating from y
nf:10;

if[2<count key `.qml;
 -1 .util.box["**"] (
  "singular value decomposition (svd) allows us to compute latent factors (off-line)";
  "and perform simple matrix multiplication to make predictions (on-line)");
 -1"compute score based on top n svd factors";
 
 / singular value decomposition

 usv:.qml.msvd 0^Y;
 -1"predict missing ratings using low rank approximations";
 P:b+ub+mb+/:{x$z$/:y} . .ml.nsvd[nf] usv;
 show rpt update score:last P from r;
 -1"compare against existing ratings";
 show rpt select from (update score:last P from r) where not null rating;
 -1"we can use svd to foldin a new user";
 .ml.foldin[.ml.nsvd[500] usv;0b] 0^Y[2];
 -1"or even a new movie";
 .ml.foldin[.ml.nsvd[500] usv;1b;0^Y[;2]];
 -1"what does the first factor look like?";
 show each {(5#x;-5#x)}([]movieId:m idesc usv[2][;0])#mlense.movie;
 -1"how much variance does each factor explain?";
 show .util.plot[40;19;.util.c10;avg] {x%sum x*:x}.qml.mdiag usv 1;
 ];

/ regularized gradient descent

-1 .util.box["**"] (
 "regularized gradient descent collaborative filtering";
 "doesn't need to be filled with default values";
 "and can use regularization");

nu:count R;nm:count R 0 / n users, n movies
n:(nu;nf)
-1"randomly initialize THETA and X";
thetax:2 raze/ THETAX:(THETA:-1+nu?/:nf#2f;X:-1+nm?/:nf#2f)

-1"learn latent factors that best predict existing ratings matrix";
thetax:first .fmincg.fmincg[100;.ml.rcfcostgrad[l1;l2;Y;n];thetax] / learn

-1"predict missing ratings";
P:b+ub+mb+/:.ml.mtm . THETAX:.ml.cfcut[n] thetax / predictions
show rpt update score:last P from r
-1"compare against existing ratings";
show rpt select from (update score:last P from r) where not null rating

-1"check collaborative filtering gradient calculations";
.util.assert . .util.rnd[1e-6] .ml.checkcfgrad[1e-4;0;.1;20 5]

/ stocastic regularized gradient descent

-1"randomly initialize THETA and X";
thetax:2 raze/ THETAX:(THETA:-1+nu?/:nf#2f;X:-1+nm?/:nf#2f)

-1"use 'where' to find list of coordinates of non-null items";
i:.ml.mwhere not null R
-1"define cost function";
cf:.ml.rcfcost[l1;l2;Y] .
-1"define minimization function";
mf:.ml.rcfupd1[l2;Y;.05f]
-1"keep running mf until improvement is lower than pct limit";

THETAX:last(.ml.converge[.0001]first::).ml.acccost[cf;{x mf/ 0N?flip i}]/(cf;::)@\:THETAX

-1"predict missing ratings";
P:b+ub+mb+/:.ml.mtm . THETAX    / predictions
show rpt update score:last P from r
-1"compare against existing ratings";
show rpt select from (update score:last P from r) where not null rating

/ weighted regularized alternating least squares

/ Large-scale Parallel Collaborative Filtering for the Netflix Prize
/ http://dl.acm.org/citation.cfm?id=1424269

-1"Alterating Least Squares is used to factor the rating matrix";
-1"into a movie matrix (X) and user matrix (THETA)";
-1"by alternating between keeping X constant and solving for THETA";
-1"and vice versa.  this changes a non-convex problem";
-1"into a quadratic problem solvable with parallel least squares.";
-1"this implementation uses a weighting scheme where";
-1"the weights are equal to the number of ratings per user/movie";

-1"reset THETA and X";
THETAX:(THETA:-1+nu?/:nf#1f;X:-1+nm?/:nf#2f)
-1"keep running mf until improvement is lower than pct limit";

THETAX:last (.ml.converge[.0001]first@).ml.acccost[cf;.ml.wrals[.1;Y]]/(cf;::)@\:THETAX

-1"predict missing ratings";
P:b+ub+mb+/:.ml.mtm . THETAX          / predictions
show rpt update score:last P from r
-1"compare against existing ratings";
show rpt select from (update score:last P from r) where not null rating
