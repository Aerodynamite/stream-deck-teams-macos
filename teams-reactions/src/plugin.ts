import streamDeck from "@elgato/streamdeck";

import {
	ApplauseAction,
	LaughAction,
	LikeAction,
	LoveAction,
	SurpriseAction,
} from "./actions/reactions";

streamDeck.logger.setLevel("info");

streamDeck.actions.registerAction(new LikeAction());
streamDeck.actions.registerAction(new LoveAction());
streamDeck.actions.registerAction(new ApplauseAction());
streamDeck.actions.registerAction(new LaughAction());
streamDeck.actions.registerAction(new SurpriseAction());

streamDeck.connect();
