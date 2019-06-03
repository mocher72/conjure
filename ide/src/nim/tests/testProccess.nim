import unittest, json, constants 
include util/main
include util/types
# include util/process
    
suite "process":
    let minionPath = testDataPath & "/sets/recursive/flagsFlagsFlags/model000001.eprime-minion"
    let eprimePath = testDataPath & "/sets/recursive/flagsFlagsFlags/model000001.eprime"
    let db = open(testDataPath & "/sets/recursive/flagsFlagsFlags/test.db", "", "", "") 
    initParser(db, minionPath, eprimePath)

    test "simple":
        let noExpression = getSimpleDomainsOfNode(db, "15", false)
        let withExpression = getSimpleDomainsOfNode(db, "15", true)
        check(noExpression.len() < withExpression.len())
        # echo noExpression

        # check(noExpression.len() < withExpression.len())

    test "pretty":
        let prettyDomains = getPrettyDomainsOfNode(db, "15")
        check(prettyDomains[0].name == "y")
        check(prettyDomains[0].rng == "int(1)")

        check(prettyDomains[1].name == "s")

        check(prettyDomains[2].name == "z")
        check(prettyDomains[2].rng == "int(1)")

        check(prettyDomains[3].name == "x")
        check(prettyDomains[3].rng == "int(1)")

suite "sanity":
    let minionPath = testDataPath & "golomb/model000001-05.eprime-minion"
    let eprimePath = testDataPath & "golomb/model000001.eprime"
    let db = open(testDataPath & "golomb/test.db", "", "", "") 
    initParser(db, minionPath, eprimePath)
    test "simpleCheckForAux":
        let withExpression = getSimpleDomainsOfNode(db, "0", true)
        # for exp in withExpression:
        #     if exp of Expression:
        #         echo exp
        #         check(not exp.name.contains("aux"))

# suite "experiment":
#     let minionPath = "/home/tom/minion-private/build/golomb/model000001-03.eprime-minion"
#     let eprimePath = "/home/tom/minion-private/build/golomb/model000001.eprime"
#     initParser(db, minionPath, eprimePath)
#     let db = open("/home/tom/minion-private/build/golomb/test.db", "", "", "") 

#     test "golomb":
#         let noExpression = getSimpleDomainsOfNode(db, "0", false)
#         # echo noExpression