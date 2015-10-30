#
# The Pref class represents the preferences of a single agent. It contains both inequalities and equalities.
#
# Inequalities are lists of length 2, e.g. the pair [3,4c] means that 
#    the agent prefers piece 4c (the piece 4 truncated once by agent c) to piece 3.
# Equalities   are lists, e.g. the list [4bb,3bb,2] means that 
#    the agent (probably agent b) is indifferent between pieces 4 truncated twice by b,
#    3 truncated twice by b and piece 2.
#
# Author: Erel Segai-Halevi
# Date:   2015-10
#
class Pref(object):
  def __init__(self,inequalities=None,equalities=None,chain=None):
    if chain and not inequalities:
      inequalities = Pref.by_chain(chain)
    self.inequalities = inequalities if inequalities else [] # each element [x,y] means "x<y".
    self.equalities   = equalities if equalities else [] # each element [x,y,z] means "x==y==z".
    self.chain        = chain
    self.cached_poset = None

  def add_inequalities(self,new_inequalities):
    self.inequalities += new_inequalities

  def add_equalities(self,new_equalities):
    self.equalities += new_equalities

  def __repr__(self):
    the_repr = ""
    for x in self.inequalities:
        the_repr += str(x[0])+"<"+str(x[1])+" "
    for x in self.equalities:
        the_repr += "=".join(map(str,x))+" "
    return the_repr

  # static variable used as default in function calls:
  __dummy = None
  
  @classmethod
  def init(cls):
    cls.__dummy = Pref([],[])

  @staticmethod 
  def by_best_piece (pieces, best_piece_index):
    """
       pieces is a list ordered from worst to best, e.g. ["1","2","3","4"].
       best_piece_index is an index to that list.
       returns a pref which means that this piece is the best.
    """
    the_prefs = []
    len_pieces = len(pieces)
    if best_piece_index<0: best_piece_index+=len_pieces
    for i in range(len_pieces):
        if i!=best_piece_index:
            the_prefs.append([pieces[i], pieces[best_piece_index]])
    return the_prefs


  @staticmethod 
  def by_chain(pieces):
    """
       pieces is a list ordered from worst to best, e.g. ["1","2","3","4"].
       returns a pref which means that each element is smaller than the next.
    """
    the_prefs = []
    for i in range(len(pieces)-1):
        the_prefs.append([pieces[i],pieces[i+1]])
    return the_prefs


  @staticmethod 
  def by_sign(sign, piece1, piece2):
    """
       returns a pref which means that piece1<piece2 
       or vice versa, depending on sign.
    """
    if not sign:
      return []
    if sign<0:
      return [ [piece1, piece2] ]
    if sign>0:
      return [ [piece2, piece1] ]
    return [ ]


  @staticmethod
  def unique(old_list):
    new_list = []
    [new_list.append(obj) for obj in old_list if obj not in new_list]
    return new_list


  @staticmethod 
  def repr_chain(chain):
    return "<".join(map(str,chain))

  def cycle(self, global_pref=Pref.__dummy):
    """ returns one cycle in this pref (if there is a cycle) """
    inequalities = Pref.unique(self.inequalities+global_pref.inequalities)
    dg = DiGraph(inequalities)
    cyc = dg.all_simple_cycles()
    if cyc: return cyc[0]
    equalities = Pref.unique(self.equalities)
    for eq in equalities:
      try:
        dg.merge_vertices(eq)
      except RuntimeError as err:
        raise RuntimeError("cannot merge equality %s. Inequalities=%s, Equalities=%s"%(eq,inequalities,equalities))
      else:
        dg.relabel({eq[0]: "("+"=".join(map(str,eq))+")"})
        cyc = dg.all_simple_cycles()
        if cyc: return cyc[0]
    return None

  def calc_poset(self, global_pref=Pref.__dummy):
    inequalities = self.inequalities+global_pref.inequalities
    eq_inequalities = []
    for eq in self.equalities:
      for x in eq:
        for y in eq:
          if x!=y:
            for ineq in inequalities:
              if ineq[0]==x:
                eq_inequalities.append([y,ineq[1]])
              if ineq[1]==x:
                eq_inequalities.append([ineq[0],y])
    inequalities += eq_inequalities 
    #print inequalities
    self.cached_poset = Poset([[],inequalities], linear_extension=False)
    return self.cached_poset

  def get_poset(self, global_pref=Pref.__dummy):
    if self.cached_poset: return self.cached_poset
    return self.calc_poset(global_pref)

  def compare(self, x, y):
    """ Safe variant of poset.compare_elements: returns None if one of the elements is not in the poset. """
    poset = self.get_poset()
    if not poset.is_parent_of(x):
        return None
    if not poset.is_parent_of(y):
        return None
    return poset.compare_elements(x,y)

  def may_be_best(self, piece, pieces_before_cutting):
    """
      Check if the agent may think that "piece" is the best, 
        when the pieces in "pieces_before_cutting" are going to be cut by another agent.
    """
    for i in reversed(self.chain):
      if i==piece:  return True     # i is better than all pieces that are not going to be cut.
      if not (i in pieces_before_cutting): return False  # i is better than a piece not going to be cut.

  def is_best(self, piece):
    return piece==self.chain[-1]

  def must_be_best(self, piece, pieces_before_cutting):
    return not (piece in pieces_before_cutting)  and  is_best(self,piece)

  def inferred_relations_between_trimmed_pieces(self, trimmed_piece, floor_piece):
    """  
       Assume that the current agent trimmed the trimmed_piece (e.g. "5cc"),
          making it equal to the floor_piece (e.g. "3")
       From this, we can infer some global relations on the piece 5. For example,
          if 3<5bb (a subjective relation), then we can infer that 5cc<5bb (a global relation).
       This functions returns these inferred relations.
    """
    poset = self.get_poset()
    inferred_relations = []
    whole_piece = trimmed_piece[0]   #  e.g. "5"
    for existing_relation in poset.cover_relations_iterator():
      if existing_relation[0]==floor_piece and existing_relation[1][0]==whole_piece:  # e.g. ["3", "5b"]
        inferred_relations.append([trimmed_piece, existing_relation[1]])              # e.g. ["5cc","5b"]
      if existing_relation[1]==floor_piece and existing_relation[0][0]==whole_piece:  # e.g. ["5b", "3"]
        inferred_relations.append([existing_relation[0], trimmed_piece])              # e.g. ["5b","5cc"]
    return inferred_relations

  def global_cover_relations_of(self, trimmed_piece):
    poset = self.get_poset()
    relations = []
    whole_piece = trimmed_piece[0]   #  e.g. "5"
    #print "global_cover_relations_of",trimmed_piece,": cover_relations=", poset.cover_relations()
    for covered_by_trimmed_piece in poset.lower_covers_iterator(trimmed_piece):
      if covered_by_trimmed_piece[0]==whole_piece and len(covered_by_trimmed_piece)>1:
        relations.append([covered_by_trimmed_piece,trimmed_piece])
    for covering_trimmed_piece in poset.upper_covers_iterator(trimmed_piece):
      if covering_trimmed_piece[0]==whole_piece and len(covering_trimmed_piece)>1:
        relations.append([trimmed_piece,covering_trimmed_piece])
    return relations


  def and_with(self,other):
    """ concatenates the preferences (equivalent to an AND operation) """
    self.inequalities += other.inequalities
    self.equalities   += other.equalities
    return self

  def __copy__(self):
    return Pref(
      inequalities=list(self.inequalities),
      equalities=list(self.equalities),
      chain=self.chain # no need to copy - does not change.
    )

print "class Pref defined." # for debug in sage notebook

Pref.init()

def Pref_examples():
	# EXAMPLES OF STATIC METHODS:
	print Pref.by_best_piece([1,2,3,4], 2)  # expects: [[1, 3], [2, 3], [4, 3]]
	print Pref.by_best_piece([1,2,3,4], -1)  # expects: [[1, 4], [2, 4], [3, 4]]
	print Pref.by_sign(-1, 5,6) + Pref.by_sign(1, 5,6) + Pref.by_sign(0, 5,6) + Pref.by_sign(None, 5,6) # expects: [[5, 6], [6, 5]]
	print Pref.unique([[1,3],[2,4],[3,1],[1,3]])  # expects: [[1, 3], [2, 4], [3, 1]]

	print Pref(chain=[1,2,3])  # expects: 1<2 2<3

	# EXAMPLE OF REPR:
	a=Pref([[1,2]]);  print a   # expects:    "1<2"
	b=Pref([],[[3,4]]);  print b   # expects:    "3=4"
	c=Pref([[1,2]],[[3,4,5]]);   print c   # expects:    "1<2 3=4=5"	

	# EXAMPLE OF COPY:
	aa=copy(a); print aa   # expects:    "1<2"
	bb=copy(b); print bb   # expects:    "3=4"
	cc=copy(c); print cc   # expects:    "1<2 3=4"

	aa.inequalities += [[5,6]]; print aa #expects: "1<2 5<6"
	print a #expects: "1<2"

	# EXAMPLE OF INFERRING RELATIONS:
	# a=Pref([["1","2"],["3","5b"],["5bb","3"],["5bbb","3"],["4b","3"],["5bbb","5bb"]]);
	# print a.inferred_relations_between_trimmed_pieces("5cc","3")         # expects [['5bb', '5cc'], ['5cc', '5b']]
	a=Pref([["1","2"],["3","5b"],["5bb","3"],["5bbb","3"],["4b","3"],["5bbb","5bb"]], equalities=[["5cc","3"]]);
	print a.global_cover_relations_of("5cc")         # expects [['5bb', '5cc'], ['5cc', '5b']]

	prefs3=[[1,2],[2,3],[4,1]]
	# EXAMPLES OF FINDING CYCLES: with only inequalities:
	print Pref(prefs3).cycle()  # expects: None
	print Pref(prefs3+[[3,1]]).cycle()  # expects: [1, 2, 3, 1]
	# with global inequalities:
	print Pref(prefs3).cycle(Pref([[3,1]]))  # expects: [1, 2, 3, 1]
	# with equalities:
	print Pref(prefs3, equalities=[[3,4]]).cycle()  # expects: [1, 2, (3=4), 1]
	print Pref(prefs3, equalities=[[4,3]]).cycle()  # expects: [1, 2, (4=3), 1]
	print Pref(prefs3+[[3,1]], equalities=[[4,3]]).cycle()  # expects: [1, 2, 3, 1]

	# EXAMPLE OF CALCULATING POSET:
	prefs3=[[1,2],[2,3],[4,1]]
	print Pref(prefs3).calc_poset().cover_relations()  # expects: [[4, 1], [1, 2], [2, 3]]
	print Pref(prefs3, equalities=[[2,5]]).calc_poset().cover_relations()  # expects: [[4, 1], [1, 2], [1, 5], [2, 3], [5, 3]]
	
	# EXAMPLE OF may_be_best:
	p=Pref(chain=["1","2","3","4"])
	print p.may_be_best("4", ["4"]),p.may_be_best("3", ["4"]),p.may_be_best("2", ["4"]),p.may_be_best("1", ["4"])  # True True False False
	print p.may_be_best("4", ["3"]),p.may_be_best("3", ["3"]),p.may_be_best("2", ["3"]),p.may_be_best("1", ["3"])  # True False False False
	print p.may_be_best("4", ["2"]),p.may_be_best("3", ["2"]),p.may_be_best("2", ["2"]),p.may_be_best("1", ["2"])  # True False False False
	print p.may_be_best("4", ["4","3"]),p.may_be_best("3", ["4","3"]),p.may_be_best("2", ["4","3"]),p.may_be_best("1", ["4","3"])  # True True True False	

