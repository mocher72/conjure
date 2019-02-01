import Mousetrap from "./util/mousetrap"
import { appendControls } from "./util/screen"
import globals from "./util/globals"
import colours from "./util/colours"
import * as listView from "./util/listView"

(function () {

    let init = true;

    window.addEventListener('message', event => {
        const message = event.data
        switch (message.command) {
            case 'loadChildren':
                globals.id2ChildIds[message.data.nodeId] = message.data.children
                update(globals.id2Node[message.data.nodeId]);
                // console.log(globals.id2ChildIds)
                // globals.tree.nodeSize([Number(message.data) * 13, 0])

                break;
            case 'loadCore':
                console.log(message.data)
                // globals.tree.nodeSize([Number(message.data) * 13, 0])
                message.data.forEach((element) => {

                    globals.correctPath.push(element.nodeId);
                });

                for (let i = 0; i < message.data.length; i++) {

                    let element = message.data[i]

                    if (!globals.id2Node[element.nodeId]) {

                        globals.addNode(element.nodeId, element.parentId, element.label);
                        globals.id2ChildIds[element.nodeId] = element.children

                        element.children.forEach(kidId => {

                            if (!globals.correctPath.includes(kidId)) {

                                globals.addNode(kidId, element.nodeId, message.data[i + 1].label.replace("!", ""))
                                globals.vscode.postMessage({
                                    command: 'loadChildren',
                                    id: kidId,
                                });
                            }

                        })
                    }
                }

                globals.collapseNode(1);

                update(globals.id2Node[0]);
                globals.waiting = false;

                globals.selectNode(globals.selectedId);

                $("#total").text(globals.totalLoaded + "/" + globals.correctPath[globals.correctPath.length - 1]);

                break;

            case 'longestBranchingVariable':
                // console.log(message.data)
                globals.tree.nodeSize([Number(message.data) * 13, 0])

                break;

            case 'loadNodes':

                // console.log(message.data);

                message.data.forEach((element) => {

                    if (!globals.id2Node[element.nodeId]) {
                        globals.addNode(element.nodeId, element.parentId, element.label);
                        globals.id2ChildIds[element.nodeId] = element.children
                    }
                });

                update(globals.id2Node[0]);
                globals.waiting = false;

                globals.selectNode(globals.selectedId);

                $("#total").text(globals.totalLoaded + "/" + globals.correctPath[globals.correctPath.length - 1]);

                break;

            case 'simpleDomains':

                listView.setNodeId(globals.selectedId);
                globals.currentDomainId += Number($("#domCount").val());

                if (globals.selectedId === 1) {
                    globals.simpleDomainsAtRoot = message.data.vars;

                    // console.log("HERE!!");

                    if (init) {
                        init = false;
                        globals.waiting = false;
                        // console.log(globals.waiting);
                        break;
                    }
                    // console.log("THERE!!");
                    // console.log(globals.waiting);

                    // console.log(globals.currentId);

                    $("#pane").empty();
                    globals.tabulate()
                    globals.appendRows(message.data.vars);
                }

                else {
                    message.data.vars.forEach(variable => {
                        $("#" + $.escapeSelector(variable.name)).removeClass("changed");

                        let li = $("#" + $.escapeSelector(variable.name) + " > :last-child");
                        li.text(variable.rng);

                        if (message.data.changedNames.includes(variable.name)) {
                            $("#" + $.escapeSelector(variable.name)).toggleClass("changed");

                        }
                    });
                }
                globals.waiting = false;

                break;

            case 'prettyDomains':

                listView.setNodeId(globals.selectedId);

                if (globals.selectedId == 1) {
                    listView.render(message.data, message.data);
                }
                else {

                    // console.log(message.data.changedExpressions)
                    listView.setChangedExpressions(message.data.changedExpressions);
                    listView.updateNodes(message.data.vars);
                    listView.setChangedList(message.data.changed);
                    listView.setChanged()
                }
                globals.waiting = false;

                break;
        }
        globals.waiting = false;
    });


    let zoom = d3.behavior.zoom()
        .on("zoom", zoomed);

    let svg = d3.select("#tree")
        .append("svg")
        .call(zoom)
        .attr("width", globals.viewerWidth)
        .attr("height", globals.viewerHeight)
        .append("g")

    function zoomed() {
        svg.attr("transform", "translate(" + d3.event.translate + ")" + " scale(" + d3.event.scale + ")")
    }


    function update(source) {
        // Compute the new tree layout.
        let nodes = globals.tree.nodes(globals.id2Node[1]).reverse(),
            links = globals.tree.links(nodes);

        // Normalize for fixed-depth.
        nodes.forEach((d) => { d.y = d.depth * 100; });
        // Declare the nodes…
        let node = svg.selectAll("g.node")
            .data(nodes, (d) => { return d.id || (d.id = ++i); });
        // Enter the nodes.
        let nodeEnter = node.enter().append("g")
            .attr("class", "node")
            .attr("id", (d) => {
                return "node" + d.id;
            })
            .attr("transform", (d) => {
                let parent = globals.id2Parent[d.id]
                if (parent) {
                    return "translate(" + parent.x + "," + parent.y + ")";
                }
            })
            .on("click", (d) => {
                globals.selectNode(d.id);
            })
        // .on("mouseover", showDomains);

        nodeEnter.append("circle")
            // .transition()
            // .duration(globals.duration)
            // .attr("r", 10)
            .attr("r", 1e-6)

        // c.attr("r", 10)

        nodeEnter.append("text")
            .attr("y", (d) => {
                // console.log(d);
                return -50
                // return d.children || d._children ? -18 : 18;
            })
            .attr("dy", ".35em")
            .attr("text-anchor", "middle")
            .text((d) => { return d.name; })
            .style("fill-opacity", 1e-6);
        // Transition nodes to their new position.
        //horizontal tree
        let nodeUpdate = node.transition()
            .duration(globals.duration)
            .attr("transform", (d) => { return "translate(" + d.x + "," + d.y + ")"; })

        nodeUpdate.select("circle")
            .attr("r", 10)
            // .attr("class", (d) => {
            .each((d) => {

                let s = "#node" + d.id + " circle";

                // console.log(s);
                let domElement = d3.select(s);
                domElement.classed("hasOthers red", false);

                let childLength = 0;
                if (d.children) {
                    childLength = d.children.length;
                }

                // if (d.id == 2) {
                    // console.log(Object.keys(globals.id2ChildIds))
                    // console.log(d)
                    // console.log(globals.id2ChildIds[1])
                    // console.log(globals.id2ChildIds[2])
                    // console.log(globals.id2ChildIds)
                // }

                if (globals.id2ChildIds[d.id]) {
                    if (childLength < globals.id2ChildIds[d.id].length) {

                        if (!globals.correctPath.includes(d.id)) {

                            domElement.classed("hasOthers red", true);

                        }
                        domElement.classed("hasOthers", true);
                    }
                }

            })

        nodeUpdate.select("text")
            .style("fill-opacity", 1);

        // console.log(nodeUpdate.select("g"));

        // Transition exiting nodes to the parent's new position.
        let nodeExit = node.exit().transition()
            .duration(globals.duration)
            .attr("transform", (d) => { return "translate(" + source.x + "," + source.y + ")"; })
            .remove();
        nodeExit.select("circle")
            .attr("r", 1e-6);
        nodeExit.select("text")
            .style("fill-opacity", 1e-6);
        // Update the links…
        // Declare the links…
        let link = svg.selectAll("path.link")
            .data(links, (d) => { return d.target.id; });
        // Enter the links.
        link.enter().insert("path", "g")
            .attr("class", (d) => {

                // console.log(d.target.id)
                // console.log(globals.correctPath)
                if (globals.correctPath.includes(d.target.id)) {
                    return "link"
                }

                return "link red";

            })
            .attr("d", (d) => {
                let o = { x: d.source.x, y: d.source.y };
                return globals.diagonal({ source: o, target: o });
            })
            .style("stroke-opacity", 1e-6);
        // Transition links to their new position.
        link.transition()
            .duration(globals.duration)
            // .duration(1000)
            .attr("d", globals.diagonal)
            .style("stroke-opacity", 1);
        // Transition exiting nodes to the parent's new position.
        link.exit().transition()
            .duration(globals.duration)
            .attr("d", (d) => {
                let o = { x: d.source.x, y: d.source.y };
                return globals.diagonal({ source: o, target: o });
            })
            .remove();

        // Stash the old positions for transition.
        nodes.forEach((d) => {
            d.x0 = d.x;
            d.y0 = d.y;
        });

    }

    globals.setup(zoom);
    appendControls();
    Mousetrap.bind('s', () => {
        globals.nextNode();
        update(globals.id2Node[globals.selectedId]);
    }, 'keydown');
    Mousetrap.bind('w', globals.upNode, 'keydown');

    Mousetrap.bind('shift', globals.previousNode, 'keydown');

    Mousetrap.bind('d', globals.rightNode, 'keydown');
    Mousetrap.bind('a', () => {
        if (globals.id2Node[globals.selectedId].children) {
            if (globals.id2Node[globals.selectedId].children.length > 1) {
                globals.nextNode();
            }
        }
    }, 'keydown');

    Mousetrap.bind('t', () => {
        globals.toggleNode(globals.selectedId);
        update(globals.id2Node[globals.selectedId]);
    }, 'keydown');

    Mousetrap.bind('c', () => {
        globals.collapseNode(globals.selectedId);
        update(globals.id2Node[globals.selectedId]);
        globals.selectNode(globals.selectedId)
    }, 'keydown');

    Mousetrap.bind('e', () => {
        globals.expandNode(globals.selectedId);
        update(globals.id2Node[globals.selectedId]);
        globals.selectNode(globals.selectedId)
    }, 'keydown');

    Mousetrap.bind('m', () => {
        globals.loadDomains(globals.selectedId);
    }, 'keydown');

    Mousetrap.bind('f', () => {
        globals.collapseFailed();
        update(globals.id2Node[globals.selectedId]);
        globals.selectNode(globals.selectedId)
        // update(globals.id2Node[1]);
    }, 'keydown');

    // globals.loadNNodes();
    // globals.selectNode(globals.selectedId);
    console.log("HELLO")
    $("#form").validate();
})()