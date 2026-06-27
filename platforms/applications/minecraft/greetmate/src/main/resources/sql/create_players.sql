CREATE TABLE players (
    id INT(11) NOT NULL AUTO_INCREMENT,
    player_name VARCHAR(36) NOT NULL,
    role INT(11) NOT NULL,
    uuid VARCHAR(36) NOT NULL,
    update_time DATETIME NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_players_uuid (uuid)
);
