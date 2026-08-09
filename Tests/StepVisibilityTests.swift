import Foundation
import SwiftData
import Testing

@testable import Remli

/// Where a roadmap step may and may not appear.
///
/// A step was filtered out of exactly one screen — the Ideas list — and left in every other
/// place that lists or counts ideas, so it went on showing up inside Spaces and padding the
/// counts while appearing to have been dealt with. These pin down the rule so the next
/// screen that lists ideas cannot quietly forget it.
@Suite("Step visibility")
struct StepVisibilityTests {

    private func makeContext() throws -> ModelContext {
        let container = try RemliSchema.makeContainer(inMemory: true)
        return ModelContext(container)
    }

    /// A goal in a Space, with one roadmap step and one loose to-do beside it.
    private func scenario(
        in context: ModelContext
    ) -> (space: IdeaCategory, goal: Idea, step: Idea, chore: Idea) {
        let space = IdeaCategory(name: "Business", isUserOwned: true)
        context.insert(space)

        let goal = Idea(text: "Client tracking app for personal trainers")
        goal.isEnriched = true
        goal.isGoal = true
        goal.category = space
        context.insert(goal)

        let step = Idea(text: "Price three suppliers", kind: .task)
        step.category = space
        context.insert(step)

        // What the workshop writes: a task that is a prerequisite for the goal.
        let link = IdeaLink(
            source: step,
            target: goal,
            kind: .prerequisiteFor,
            rationale: "Needed before the build can start.",
            strength: 0.8,
            origin: .user
        )
        context.insert(link)

        // An ordinary to-do, filed in the same Space, joined to nothing.
        let chore = Idea(text: "Renew the gym insurance", kind: .task)
        chore.category = space
        context.insert(chore)

        return (space, goal, step, chore)
    }

    @Test("A workshop step is recognised as a step")
    func stepsAreIdentified() throws {
        let context = try makeContext()
        let world = scenario(in: context)

        #expect(world.step.isRoadmapStep)
        #expect(world.chore.isRoadmapStep == false, "a loose to-do is not a roadmap step")
        #expect(world.goal.isRoadmapStep == false, "the goal is not its own step")
    }

    @Test("Steps are dropped from an idea listing, to-dos are not")
    func filteringKeepsChores() throws {
        let context = try makeContext()
        let world = scenario(in: context)

        let listed = [world.goal, world.step, world.chore].excludingSteps.map(\.id)
        #expect(listed.contains(world.goal.id))
        #expect(listed.contains(world.chore.id))
        #expect(!listed.contains(world.step.id), "a step leaked into an idea listing")
    }

    @Test("A Space's count does not include its steps")
    func spaceCountExcludesSteps() throws {
        let context = try makeContext()
        let world = scenario(in: context)

        // Goal plus the loose to-do. Not the step.
        #expect(world.space.ideaCount == 2)
        #expect(world.space.totalIdeaCount == 2)
    }

    @Test("A Collection's steps do not inflate its Space's count either")
    func nestedCountExcludesSteps() throws {
        let context = try makeContext()
        let space = IdeaCategory(name: "Business", isUserOwned: true)
        context.insert(space)
        let collection = IdeaCategory(name: "Trainer tools", parent: space, isUserOwned: true)
        context.insert(collection)

        let goal = Idea(text: "The app")
        goal.category = collection
        goal.isGoal = true
        context.insert(goal)

        let step = Idea(text: "Sketch the schema", kind: .task)
        step.category = collection
        context.insert(step)
        context.insert(
            IdeaLink(
                source: step, target: goal, kind: .prerequisiteFor,
                rationale: "First.", strength: 0.9, origin: .user
            )
        )

        #expect(collection.ideaCount == 1)
        #expect(space.totalIdeaCount == 1)
    }

    @Test("Detaching a step from its roadmap turns it back into an ordinary to-do")
    func rejectingALinkReleasesTheStep() throws {
        let context = try makeContext()
        let world = scenario(in: context)

        let link = try #require((world.step.outgoingLinks ?? []).first)
        link.reject()

        #expect(world.step.isRoadmapStep == false)
        #expect([world.goal, world.step].excludingSteps.count == 2)
    }

    @Test("Steps never reach the map, because the map has no tasks on it at all")
    func mapHasNoSteps() throws {
        let context = try makeContext()
        let world = scenario(in: context)

        let graph = IdeaGraph(ideas: [world.goal, world.step, world.chore])
        #expect(graph.node(world.step.id) == nil)
        #expect(graph.node(world.chore.id) == nil)
        #expect(graph.node(world.goal.id) != nil)
    }
}

/// Node colour follows the Space, not whatever Collection the idea happens to sit in.
@Suite("Map node colour")
struct MapNodeColorTests {

    private func makeContext() throws -> ModelContext {
        let container = try RemliSchema.makeContainer(inMemory: true)
        return ModelContext(container)
    }

    @Test("An idea in a Collection takes its Space's colour")
    func collectionInheritsSpaceColour() throws {
        let context = try makeContext()
        let space = IdeaCategory(name: "Business", isUserOwned: true)
        context.insert(space)
        space.setColor(.teal)

        let collection = IdeaCategory(name: "Trainer tools", parent: space, isUserOwned: true)
        context.insert(collection)

        let idea = Idea(text: "Client tracking app")
        idea.isEnriched = true
        idea.category = collection
        context.insert(idea)

        #expect(idea.spaceColorHex == SpaceColor.teal.hex)

        let graph = IdeaGraph(ideas: [idea])
        #expect(try #require(graph.node(idea.id)).colorHex == SpaceColor.teal.hex)
    }

    @Test("A Collection that drifted still draws in its Space's colour")
    func driftedCollectionDoesNotWin() throws {
        let context = try makeContext()
        let space = IdeaCategory(name: "Business", isUserOwned: true)
        context.insert(space)
        space.setColor(.moss)

        let collection = IdeaCategory(name: "Trainer tools", parent: space, isUserOwned: true)
        context.insert(collection)
        // However this happened — an old build, a half-finished cascade — the map must not
        // show a node in a colour that matches no filter chip.
        collection.colorHex = "123456"

        let idea = Idea(text: "Client tracking app")
        idea.isEnriched = true
        idea.category = collection
        context.insert(idea)

        let graph = IdeaGraph(ideas: [idea])
        #expect(try #require(graph.node(idea.id)).colorHex == SpaceColor.moss.hex)
    }

    @Test("Recolouring a Space recolours its nodes")
    func recolouringFollowsThrough() throws {
        let context = try makeContext()
        let space = IdeaCategory(name: "Business", isUserOwned: true)
        context.insert(space)

        let idea = Idea(text: "Client tracking app")
        idea.isEnriched = true
        idea.category = space
        context.insert(idea)

        space.setColor(.lagoon)
        #expect(try #require(IdeaGraph(ideas: [idea]).node(idea.id)).colorHex == SpaceColor.lagoon.hex)

        space.setColor(.rust)
        #expect(try #require(IdeaGraph(ideas: [idea]).node(idea.id)).colorHex == SpaceColor.rust.hex)
    }

    @Test("An idea in no Space has no colour of its own")
    func unfiledIdeasFallBack() throws {
        let context = try makeContext()
        let idea = Idea(text: "Unfiled")
        idea.isEnriched = true
        context.insert(idea)

        #expect(idea.spaceColorHex == nil)
        #expect(try #require(IdeaGraph(ideas: [idea]).node(idea.id)).colorHex == nil)
    }
}
